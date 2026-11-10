-- Admin → Backup. A signed-in admin can download the live public schema
-- (tables, SQL functions, triggers, row-level security, grants) and every
-- row, then put that file back.
--
-- Edge Function source and dashboard secrets are not in Postgres, so they
-- are not in the file. Auth sessions are left out on purpose.
--
-- Restore uploads into staging tables first. Replacing live rows happens in
-- one transaction, so a failed restore does not leave a half-applied database.

-- ---------------------------------------------------------------------------
-- Staging. No API access. security definer functions are the only writers.
-- ---------------------------------------------------------------------------

create table public.admin_restore_runs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid not null,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  restore_auth boolean not null default false,
  tables text[] not null
);

create table public.admin_restore_staging (
  id bigserial primary key,
  run_id uuid not null references public.admin_restore_runs (id) on delete cascade,
  schema_name text not null,
  table_name text not null,
  rows_data jsonb not null,
  created_at timestamptz not null default now(),
  constraint admin_restore_staging_schema check (schema_name in ('public', 'auth')),
  constraint admin_restore_staging_table check (table_name ~ '^[a-z_][a-z0-9_]*$')
);

create index admin_restore_staging_run
  on public.admin_restore_staging (run_id, schema_name, table_name, id);

comment on table public.admin_restore_runs is
  'One admin restore upload. Live rows are not replaced until admin_restore_commit.';

comment on table public.admin_restore_staging is
  'Backup chunks waiting for admin_restore_commit. Holds password hashes while an upload is in progress.';

alter table public.admin_restore_runs enable row level security;
alter table public.admin_restore_staging enable row level security;

revoke all on table public.admin_restore_runs from public, anon, authenticated, service_role;
revoke all on table public.admin_restore_staging from public, anon, authenticated, service_role;

do $$
declare
  v_seq text := pg_get_serial_sequence('public.admin_restore_staging', 'id');
begin
  if v_seq is not null then
    execute format(
      'revoke all on sequence %s from public, anon, authenticated, service_role',
      v_seq
    );
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Shared helpers. Not granted to the API.
-- ---------------------------------------------------------------------------

create or replace function public.admin_backup_guard()
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
begin
  -- The signed-in role's timeout is often a few seconds. A backup chunk
  -- and the final restore transaction need longer.
  perform set_config('statement_timeout', '180000', true);
  perform public.assert_admin();
end;
$$;

create or replace function public.admin_backup_load_order()
returns text[]
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_all text[];
  v_pending text[];
  v_order text[] := '{}';
  v_name text;
begin
  select coalesce(array_agg(c.relname order by c.relname), '{}')
  into v_all
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relkind in ('r', 'p')
    and c.relname not in ('admin_restore_runs', 'admin_restore_staging')
    and not exists (
      select 1
      from pg_depend d
      where d.objid = c.oid
        and d.deptype = 'e'
    );

  v_pending := v_all;
  while cardinality(v_pending) > 0 loop
    select t
    into v_name
    from unnest(v_pending) as t
    where not exists (
      select 1
      from pg_constraint con
      join pg_class child on child.oid = con.conrelid
      join pg_namespace nc on nc.oid = child.relnamespace
      join pg_class parent on parent.oid = con.confrelid
      join pg_namespace np on np.oid = parent.relnamespace
      where con.contype = 'f'
        and nc.nspname = 'public'
        and child.relname = t
        and np.nspname = 'public'
        and parent.relname <> child.relname
        and parent.relname = any (v_pending)
    )
    order by t
    limit 1;

    if v_name is null then
      v_order := v_order || v_pending;
      exit;
    end if;

    v_order := v_order || v_name;
    v_pending := array_remove(v_pending, v_name);
  end loop;

  return v_order;
end;
$$;

create or replace function public.admin_backup_order_by(p_rel regclass)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_order text;
begin
  if p_rel is null then
    return 'ctid';
  end if;

  select string_agg(quote_ident(a.attname), ', ' order by u.ord)
  into v_order
  from pg_index i
  join lateral unnest(i.indkey) with ordinality as u(attnum, ord) on true
  join pg_attribute a
    on a.attrelid = i.indrelid
   and a.attnum = u.attnum
  where i.indrelid = p_rel
    and i.indisprimary
    and u.attnum > 0
    and not exists (
      select 1
      from unnest(i.indkey) as k
      where k = 0
    );

  return coalesce(v_order, 'ctid');
end;
$$;

-- p_on is already a safe SQL fragment such as 'TABLE public.questions'.
create or replace function public.admin_backup_acl_sql(
  p_acl aclitem[],
  p_default_kind "char",
  p_owner oid,
  p_on text
) returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_sql text := '';
  r record;
  v_who text;
begin
  v_sql := format(
    E'REVOKE ALL ON %s FROM PUBLIC, anon, authenticated, service_role;\n',
    p_on
  );

  for r in
    select privilege_type, is_grantable, grantee
    from aclexplode(coalesce(p_acl, acldefault(p_default_kind, p_owner)))
  loop
    if r.grantee = 0 then
      v_who := 'PUBLIC';
    else
      v_who := pg_get_userbyid(r.grantee);
      if v_who is null then
        continue;
      end if;
      v_who := quote_ident(v_who);
    end if;

    v_sql := v_sql || format(
      E'GRANT %s ON %s TO %s%s;\n',
      r.privilege_type,
      p_on,
      v_who,
      case when r.is_grantable then ' WITH GRANT OPTION' else '' end
    );
  end loop;

  return v_sql;
end;
$$;

create or replace function public.admin_restore_write(
  p_table text,
  p_rows jsonb
) returns integer
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_rel regclass;
  v_parsed jsonb;
  v_cols text[];
  v_pk_names text[];
  v_list text;
  v_pk text;
  v_set text;
  v_override boolean;
  v_count integer;
begin
  if p_table is null or p_table !~ '^[a-z_][a-z0-9_]*$' then
    raise exception 'Unknown table.';
  end if;
  if p_table in ('admin_restore_runs', 'admin_restore_staging') then
    raise exception 'Unknown table.';
  end if;

  select c.oid::regclass
  into v_rel
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname = p_table
    and c.relkind in ('r', 'p');

  if v_rel is null then
    raise exception 'Unknown table.';
  end if;

  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    raise exception 'Backup rows must be a list.';
  end if;
  if jsonb_array_length(p_rows) = 0 then
    return 0;
  end if;

  select jsonb_agg(
    case jsonb_typeof(elem)
      when 'string' then (elem #>> '{}')::jsonb
      when 'object' then elem
      else null
    end
  )
  into v_parsed
  from jsonb_array_elements(p_rows) as elem;

  if v_parsed is null then
    return 0;
  end if;

  select coalesce(array_agg(a.attname order by a.attnum), '{}')
  into v_cols
  from pg_attribute a
  where a.attrelid = v_rel
    and a.attnum > 0
    and not a.attisdropped
    and a.attgenerated = ''
    and exists (
      select 1
      from jsonb_array_elements(v_parsed) as e
      where e ? a.attname
    );

  if cardinality(v_cols) = 0 then
    raise exception 'Backup has no writable columns for %.', p_table;
  end if;

  select jsonb_agg(stripped)
  into v_parsed
  from (
    select (
      select jsonb_object_agg(c, elem -> c)
      from unnest(v_cols) as c
      where elem ? c
    ) as stripped
    from jsonb_array_elements(v_parsed) as elem
  ) as s
  where stripped is not null;

  if v_parsed is null then
    return 0;
  end if;

  select string_agg(quote_ident(c), ', ' order by ord)
  into v_list
  from unnest(v_cols) with ordinality as u(c, ord);

  select exists (
    select 1
    from pg_attribute a
    where a.attrelid = v_rel
      and a.attidentity in ('a', 'd')
  )
  into v_override;

  select coalesce(array_agg(a.attname order by u.ord), '{}')
  into v_pk_names
  from pg_index i
  join lateral unnest(i.indkey) with ordinality as u(attnum, ord) on true
  join pg_attribute a
    on a.attrelid = i.indrelid
   and a.attnum = u.attnum
  where i.indrelid = v_rel
    and i.indisprimary
    and u.attnum > 0
    and not exists (
      select 1
      from unnest(i.indkey) as k
      where k = 0
    );

  if cardinality(v_pk_names) = 0 or not (v_pk_names <@ v_cols) then
    v_pk := null;
    v_pk_names := '{}';
  else
    select string_agg(quote_ident(c), ', ' order by ord)
    into v_pk
    from unnest(v_pk_names) with ordinality as u(c, ord);
  end if;

  select string_agg(format('%I = excluded.%I', c, c), ', ' order by ord)
  into v_set
  from unnest(v_cols) with ordinality as u(c, ord)
  where not (c = any (v_pk_names));

  if v_pk is null then
    execute format(
      'insert into public.%I (%s) %s select %s from jsonb_populate_recordset(null::public.%I, $1)',
      p_table,
      v_list,
      case when v_override then 'overriding system value' else '' end,
      v_list,
      p_table
    )
    using v_parsed;
  elsif v_set is null then
    execute format(
      'insert into public.%I (%s) %s select %s from jsonb_populate_recordset(null::public.%I, $1) on conflict (%s) do nothing',
      p_table,
      v_list,
      case when v_override then 'overriding system value' else '' end,
      v_list,
      p_table,
      v_pk
    )
    using v_parsed;
  else
    execute format(
      'insert into public.%I (%s) %s select %s from jsonb_populate_recordset(null::public.%I, $1) on conflict (%s) do update set %s',
      p_table,
      v_list,
      case when v_override then 'overriding system value' else '' end,
      v_list,
      p_table,
      v_pk,
      v_set
    )
    using v_parsed;
  end if;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

create or replace function public.admin_restore_auth_write(
  p_table text,
  p_rows jsonb
) returns integer
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_rel regclass;
  v_parsed jsonb;
  v_cols text[];
  v_list text;
  v_set text;
  v_instance uuid;
  v_count integer;
begin
  if p_table not in ('users', 'identities') then
    raise exception 'Unknown auth table.';
  end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    raise exception 'Backup rows must be a list.';
  end if;
  if jsonb_array_length(p_rows) = 0 then
    return 0;
  end if;

  v_rel := format('auth.%I', p_table)::regclass;

  select jsonb_agg(
    case jsonb_typeof(elem)
      when 'string' then (elem #>> '{}')::jsonb
      when 'object' then elem
      else null
    end
  )
  into v_parsed
  from jsonb_array_elements(p_rows) as elem;

  if p_table = 'users'
     and exists (
       select 1
       from pg_attribute a
       where a.attrelid = v_rel
         and a.attname = 'instance_id'
         and not a.attisdropped
     )
  then
    select u.instance_id
    into v_instance
    from auth.users as u
    where u.id = auth.uid();

    if v_instance is not null then
      select jsonb_agg(elem || jsonb_build_object('instance_id', v_instance))
      into v_parsed
      from jsonb_array_elements(v_parsed) as elem;
    end if;
  end if;

  select coalesce(array_agg(a.attname order by a.attnum), '{}')
  into v_cols
  from pg_attribute a
  where a.attrelid = v_rel
    and a.attnum > 0
    and not a.attisdropped
    and a.attgenerated = ''
    and exists (
      select 1
      from jsonb_array_elements(v_parsed) as e
      where e ? a.attname
    );

  if cardinality(v_cols) = 0 or not ('id' = any (v_cols)) then
    raise exception 'Backup has no id column for auth.%.', p_table;
  end if;

  select jsonb_agg(stripped)
  into v_parsed
  from (
    select (
      select jsonb_object_agg(c, elem -> c)
      from unnest(v_cols) as c
      where elem ? c
    ) as stripped
    from jsonb_array_elements(v_parsed) as elem
  ) as s
  where stripped is not null;

  select string_agg(quote_ident(c), ', ' order by ord)
  into v_list
  from unnest(v_cols) with ordinality as u(c, ord);

  select string_agg(format('%I = excluded.%I', c, c), ', ' order by ord)
  into v_set
  from unnest(v_cols) with ordinality as u(c, ord)
  where c <> 'id';

  execute format(
    'insert into auth.%I (%s) select %s from jsonb_populate_recordset(null::auth.%I, $1) on conflict (id) do update set %s',
    p_table,
    v_list,
    v_list,
    p_table,
    coalesce(v_set, 'id = excluded.id')
  )
  using v_parsed;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- ---------------------------------------------------------------------------
-- Export
-- ---------------------------------------------------------------------------

create or replace function public.admin_backup_manifest()
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_order text[];
  v_name text;
  v_count bigint;
  v_tables jsonb := '[]'::jsonb;
  v_total bigint := 0;
  v_users bigint := 0;
  v_identities bigint := 0;
  v_notes jsonb;
begin
  perform public.admin_backup_guard();
  v_order := public.admin_backup_load_order();

  foreach v_name in array v_order loop
    execute format('select count(*) from public.%I', v_name) into v_count;
    v_total := v_total + v_count;
    v_tables := v_tables || jsonb_build_array(
      jsonb_build_object('name', v_name, 'rows', v_count)
    );
  end loop;

  begin
    select count(*) into v_users from auth.users;
  exception
    when undefined_table then
      v_users := 0;
  end;

  begin
    select count(*) into v_identities from auth.identities;
  exception
    when undefined_table then
      v_identities := 0;
  end;

  v_notes := jsonb_build_array(
    'Edge Function source and the secret keys those functions use. The code is in the git repo under supabase/functions. Secrets stay in the Supabase dashboard.',
    'Sign-in sessions and refresh tokens. People sign in again after a restore.',
    'Vault secrets and API keys.'
  );

  perform public.admin_log_action(
    'backup_export',
    null,
    jsonb_build_object('tables', cardinality(v_order), 'rows', v_total)
  );

  return jsonb_build_object(
    'format', 'medcain-backup',
    'version', 1,
    'generated_at', clock_timestamp(),
    'postgres_version', current_setting('server_version'),
    'load_order', to_jsonb(v_order),
    'tables', v_tables,
    'row_count', v_total,
    'auth_users', v_users,
    'auth_identities', v_identities,
    'not_included', v_notes
  );
end;
$$;

create or replace function public.admin_backup_schema()
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_sql text := '';
  v_reset text := '';
  v_piece text;
  r record;
  v_cols text;
  v_views oid[];
  v_pending oid[];
  v_pick oid;
  v_storage bigint := 0;
begin
  perform public.admin_backup_guard();

  v_sql := format(
    E'-- MEDCAIN backup of the public schema.\n-- Generated at %s.\n-- Postgres %s.\n--\n-- Rebuilds types, tables, indexes, views, SQL functions, triggers,\n-- row-level security, and grants. Does not load table rows.\n-- Does not include Edge Functions or secret keys.\n--\n-- Run this on an empty public schema. To empty it, run reset_public_sql\n-- from the same backup file first. That script deletes public data.\n-- After the schema exists, sign in as an admin and use Admin → Backup\n-- to load the rows from the backup file.\n\nSET check_function_bodies = off;
SET search_path = public, auth;\n\n',
    clock_timestamp(),
    current_setting('server_version')
  );

  begin
    if to_regclass('storage.objects') is not null then
      execute 'select count(*) from storage.objects' into v_storage;
      if v_storage > 0 then
        v_sql := v_sql || E'-- Storage file bytes are not in this backup.\n\n';
      end if;
    end if;
  exception
    when others then
      null;
  end;

  -- Schema privileges, when Postgres stored them explicitly.
  select n.nspacl, n.nspowner
  into r
  from pg_namespace n
  where n.nspname = 'public';

  if r.nspacl is not null then
    v_sql := v_sql || public.admin_backup_acl_sql(
      r.nspacl, 'n'::"char", r.nspowner, 'SCHEMA public'
    ) || E'\n';
  end if;

  v_sql := v_sql || E'-- Types\n';
  for r in
    select format(
      'CREATE TYPE %I.%I AS ENUM (%s);',
      n.nspname,
      t.typname,
      (
        select string_agg(quote_literal(e.enumlabel), ', ' order by e.enumsortorder)
        from pg_enum e
        where e.enumtypid = t.oid
      )
    ) as stmt
    from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'public'
      and t.typtype = 'e'
    order by t.typname
  loop
    v_sql := v_sql || r.stmt || E'\n';
  end loop;

  for r in
    select format(
      'CREATE DOMAIN %I.%I AS %s%s;',
      n.nspname,
      t.typname,
      pg_catalog.format_type(t.typbasetype, t.typtypmod),
      coalesce(
        (
          select string_agg(' ' || pg_get_constraintdef(c.oid), '' order by c.oid)
          from pg_constraint c
          where c.contypid = t.oid
        ),
        ''
      )
    ) as stmt
    from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'public'
      and t.typtype = 'd'
    order by t.typname
  loop
    v_sql := v_sql || r.stmt || E'\n';
  end loop;

  for r in
    select format(
      'CREATE TYPE %I.%I AS (%s);',
      n.nspname,
      t.typname,
      (
        select string_agg(
          format(
            '%I %s',
            a.attname,
            pg_catalog.format_type(a.atttypid, a.atttypmod)
          ),
          ', ' order by a.attnum
        )
        from pg_attribute a
        where a.attrelid = c.oid
          and a.attnum > 0
          and not a.attisdropped
      )
    ) as stmt
    from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    join pg_class c on c.oid = t.typrelid and c.relkind = 'c'
    where n.nspname = 'public'
      and t.typtype = 'c'
    order by t.typname
  loop
    v_sql := v_sql || r.stmt || E'\n';
  end loop;

  v_sql := v_sql || E'\n-- Sequences\n';
  for r in
    select format(
      'CREATE SEQUENCE %I.%I AS %s INCREMENT BY %s MINVALUE %s MAXVALUE %s START WITH %s CACHE %s %sCYCLE;',
      ps.schemaname,
      ps.sequencename,
      ps.data_type,
      ps.increment_by,
      ps.min_value,
      ps.max_value,
      ps.start_value,
      ps.cache_size,
      case when ps.cycle then '' else 'NO ' end
    ) as stmt
    from pg_class s
    join pg_namespace n on n.oid = s.relnamespace
    join pg_sequences ps
      on ps.schemaname = n.nspname
     and ps.sequencename = s.relname
    where n.nspname = 'public'
      and s.relkind = 'S'
      and not exists (
        select 1
        from pg_depend d
        where d.objid = s.oid
          and d.deptype in ('i', 'e')
      )
    order by s.relname
  loop
    v_sql := v_sql || r.stmt || E'\n';
  end loop;

  v_sql := v_sql || E'\n-- Tables\n';
  for r in
    select c.oid, n.nspname, c.relname
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind in ('r', 'p')
      and not exists (
        select 1
        from pg_depend d
        where d.objid = c.oid
          and d.deptype = 'e'
      )
    order by c.relname
  loop
    select string_agg(
      format(
        '%I %s%s%s',
        a.attname,
        pg_catalog.format_type(a.atttypid, a.atttypmod),
        case
          when a.attidentity = 'a' then ' GENERATED ALWAYS AS IDENTITY'
          when a.attidentity = 'd' then ' GENERATED BY DEFAULT AS IDENTITY'
          when a.attgenerated = 's' then
            ' GENERATED ALWAYS AS (' || pg_get_expr(ad.adbin, ad.adrelid) || ') STORED'
          when ad.adbin is not null then
            ' DEFAULT ' || pg_get_expr(ad.adbin, ad.adrelid)
          else ''
        end,
        case when a.attnotnull then ' NOT NULL' else '' end
      ),
      E',\n  ' order by a.attnum
    )
    into v_cols
    from pg_attribute a
    left join pg_attrdef ad
      on ad.adrelid = a.attrelid
     and ad.adnum = a.attnum
    where a.attrelid = r.oid
      and a.attnum > 0
      and not a.attisdropped;

    v_sql := v_sql || format(
      E'CREATE TABLE %I.%I (\n  %s\n);\n',
      r.nspname,
      r.relname,
      coalesce(v_cols, '')
    );
  end loop;

  v_sql := v_sql || E'\n-- Sequence ownership\n';
  for r in
    select format(
      'ALTER SEQUENCE %I.%I OWNED BY %I.%I.%I;',
      sn.nspname,
      seq.relname,
      tn.nspname,
      parent.relname,
      a.attname
    ) as stmt
    from pg_depend d
    join pg_class seq on seq.oid = d.objid and seq.relkind = 'S'
    join pg_namespace sn on sn.oid = seq.relnamespace
    join pg_class parent on parent.oid = d.refobjid
    join pg_namespace tn on tn.oid = parent.relnamespace
    join pg_attribute a
      on a.attrelid = parent.oid
     and a.attnum = d.refobjsubid
    where d.deptype = 'a'
      and d.classid = 'pg_class'::regclass
      and tn.nspname = 'public'
      and not a.attisdropped
    order by seq.relname
  loop
    v_sql := v_sql || r.stmt || E'\n';
  end loop;

  v_sql := v_sql || E'\n-- Constraints\n';
  for r in
    select format(
      'ALTER TABLE %I.%I ADD CONSTRAINT %I %s;',
      n.nspname,
      c.relname,
      con.conname,
      pg_get_constraintdef(con.oid)
    ) as stmt
    from pg_constraint con
    join pg_class c on c.oid = con.conrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and con.contype in ('p', 'u', 'c', 'x')
    order by c.relname, con.conname
  loop
    v_sql := v_sql || r.stmt || E'\n';
  end loop;

  v_sql := v_sql || E'\n-- Indexes\n';
  for r in
    select pg_get_indexdef(i.indexrelid) || ';' as stmt
    from pg_index i
    join pg_class c on c.oid = i.indrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and not exists (
        select 1
        from pg_constraint con
        where con.conindid = i.indexrelid
      )
    order by c.relname, i.indexrelid
  loop
    v_sql := v_sql || r.stmt || E'\n';
  end loop;

  v_sql := v_sql || E'\n-- Foreign keys\n';
  for r in
    select format(
      'ALTER TABLE %I.%I ADD CONSTRAINT %I %s;',
      n.nspname,
      c.relname,
      con.conname,
      pg_get_constraintdef(con.oid)
    ) as stmt
    from pg_constraint con
    join pg_class c on c.oid = con.conrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and con.contype = 'f'
    order by c.relname, con.conname
  loop
    v_sql := v_sql || r.stmt || E'\n';
  end loop;

  -- SQL functions may mention views that are created just below.
  -- check_function_bodies is off so those forward references are allowed.
  v_sql := v_sql || E'\n-- Functions\n';
  for r in
    select p.oid
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prokind in ('f', 'p', 'w')
      and not exists (
        select 1
        from pg_depend d
        where d.objid = p.oid
          and d.deptype = 'e'
      )
    order by p.proname, p.oid
  loop
    begin
      v_sql := v_sql || pg_get_functiondef(r.oid) || E';\n\n';
    exception
      when others then
        v_sql := v_sql || format(E'-- Skipped function %s: %s\n\n', r.oid, sqlerrm);
    end;
  end loop;

  v_sql := v_sql || E'-- Views\n';
  select coalesce(array_agg(c.oid order by c.relname), '{}')
  into v_views
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relkind in ('v', 'm');

  v_pending := v_views;
  while cardinality(v_pending) > 0 loop
    select c.oid
    into v_pick
    from pg_class c
    where c.oid = any (v_pending)
      and not exists (
        select 1
        from pg_depend d
        join pg_rewrite rw
          on rw.oid = d.objid
         and d.classid = 'pg_rewrite'::regclass
        join pg_class dep
          on dep.oid = d.refobjid
         and d.refclassid = 'pg_class'::regclass
        where rw.ev_class = c.oid
          and dep.oid = any (v_pending)
          and dep.oid <> c.oid
          and dep.relkind in ('v', 'm')
      )
    order by c.relname
    limit 1;

    if v_pick is null then
      v_pick := v_pending[1];
    end if;

    select case
      when c.relkind = 'm' then format(
        E'CREATE MATERIALIZED VIEW %I.%I AS\n%s;\n',
        n.nspname,
        c.relname,
        regexp_replace(btrim(pg_get_viewdef(c.oid, true)), ';+\s*$', '')
      )
      else format(
        E'CREATE VIEW %I.%I%s AS\n%s;\n',
        n.nspname,
        c.relname,
        case
          when c.reloptions is null then ''
          else ' WITH (' || array_to_string(c.reloptions, ', ') || ')'
        end,
        regexp_replace(btrim(pg_get_viewdef(c.oid, true)), ';+\s*$', '')
      )
    end
    into v_piece
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where c.oid = v_pick;

    v_sql := v_sql || coalesce(v_piece, '');
    v_pending := array_remove(v_pending, v_pick);
  end loop;

  v_sql := v_sql || E'\n-- Triggers\n';
  for r in
    select pg_get_triggerdef(t.oid, true) || E';\n' as stmt
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and not t.tgisinternal
    order by c.relname, t.tgname
  loop
    v_sql := v_sql || r.stmt;
  end loop;

  v_sql := v_sql || E'\n-- Triggers on other schemas that call public functions\n';
  for r in
    select format(
      E'DROP TRIGGER IF EXISTS %I ON %I.%I;\n%s;\n',
      t.tgname,
      n.nspname,
      c.relname,
      pg_get_triggerdef(t.oid, true)
    ) as stmt
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    join pg_proc p on p.oid = t.tgfoid
    join pg_namespace pn on pn.oid = p.pronamespace
    where not t.tgisinternal
      and pn.nspname = 'public'
      and n.nspname <> 'public'
    order by n.nspname, c.relname, t.tgname
  loop
    v_sql := v_sql || r.stmt;
  end loop;

  v_sql := v_sql || E'\n-- Row level security\n';
  for r in
    select c.relname, c.relrowsecurity, c.relforcerowsecurity
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind in ('r', 'p')
      and (c.relrowsecurity or c.relforcerowsecurity)
    order by c.relname
  loop
    if r.relrowsecurity then
      v_sql := v_sql || format(
        E'ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;\n',
        r.relname
      );
    end if;
    if r.relforcerowsecurity then
      v_sql := v_sql || format(
        E'ALTER TABLE public.%I FORCE ROW LEVEL SECURITY;\n',
        r.relname
      );
    end if;
  end loop;

  for r in
    select
      pol.polname,
      n.nspname,
      c.relname,
      pol.polpermissive,
      pol.polcmd,
      pol.polroles,
      pol.polqual,
      pol.polwithcheck,
      pol.polrelid
    from pg_policy pol
    join pg_class c on c.oid = pol.polrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
    order by c.relname, pol.polname
  loop
    select coalesce(string_agg(
      case
        when rol = 0 then 'PUBLIC'
        else quote_ident(pg_get_userbyid(rol))
      end,
      ', ' order by rol
    ), 'PUBLIC')
    into v_piece
    from unnest(r.polroles) as rol
    where rol = 0 or pg_get_userbyid(rol) is not null;

    v_sql := v_sql || format(
      'CREATE POLICY %I ON %I.%I AS %s FOR %s TO %s',
      r.polname,
      r.nspname,
      r.relname,
      case when r.polpermissive then 'PERMISSIVE' else 'RESTRICTIVE' end,
      case r.polcmd
        when 'r' then 'SELECT'
        when 'a' then 'INSERT'
        when 'w' then 'UPDATE'
        when 'd' then 'DELETE'
        else 'ALL'
      end,
      coalesce(nullif(v_piece, ''), 'PUBLIC')
    );
    if r.polqual is not null then
      v_sql := v_sql || ' USING (' || pg_get_expr(r.polqual, r.polrelid) || ')';
    end if;
    if r.polwithcheck is not null then
      v_sql := v_sql || ' WITH CHECK (' || pg_get_expr(r.polwithcheck, r.polrelid) || ')';
    end if;
    v_sql := v_sql || E';\n';
  end loop;

  v_sql := v_sql || E'\n-- Grants\n';
  for r in
    select
      c.relacl,
      c.relowner,
      c.relkind,
      case
        when c.relkind = 'S' then format('SEQUENCE %I.%I', n.nspname, c.relname)
        else format('TABLE %I.%I', n.nspname, c.relname)
      end as target,
      case when c.relkind = 'S' then 'S'::"char" else 'r'::"char" end as kind
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind in ('r', 'p', 'v', 'm', 'S')
    order by c.relkind, c.relname
  loop
    v_sql := v_sql || public.admin_backup_acl_sql(r.relacl, r.kind, r.relowner, r.target);
  end loop;

  for r in
    select format(
      'GRANT %s (%s) ON TABLE %I.%I TO %s%s;',
      privilege_type,
      string_agg(quote_ident(attname), ', ' order by attname),
      nspname,
      relname,
      who,
      case when is_grantable then ' WITH GRANT OPTION' else '' end
    ) as stmt
    from (
      select
        n.nspname,
        c.relname,
        a.attname,
        x.privilege_type,
        x.is_grantable,
        case
          when x.grantee = 0 then 'PUBLIC'
          else quote_ident(pg_get_userbyid(x.grantee))
        end as who
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      join pg_attribute a on a.attrelid = c.oid
      cross join lateral aclexplode(a.attacl) as x
      where n.nspname = 'public'
        and c.relkind in ('r', 'p')
        and a.attacl is not null
        and a.attnum > 0
        and not a.attisdropped
    ) as s
    where who is not null
    group by nspname, relname, privilege_type, is_grantable, who
  loop
    v_sql := v_sql || r.stmt || E'\n';
  end loop;

  for r in
    select
      p.proacl,
      p.proowner,
      case
        when p.prokind = 'p' then format(
          'PROCEDURE %I.%I(%s)',
          n.nspname,
          p.proname,
          pg_get_function_identity_arguments(p.oid)
        )
        else format(
          'FUNCTION %I.%I(%s)',
          n.nspname,
          p.proname,
          pg_get_function_identity_arguments(p.oid)
        )
      end as target
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prokind in ('f', 'p', 'w')
      and not exists (
        select 1
        from pg_depend d
        where d.objid = p.oid
          and d.deptype = 'e'
      )
    order by p.proname, p.oid
  loop
    v_sql := v_sql || public.admin_backup_acl_sql(
      r.proacl, 'f'::"char", r.proowner, r.target
    );
  end loop;

  for r in
    select t.typacl, t.typowner, format('TYPE %I.%I', n.nspname, t.typname) as target
    from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'public'
      and t.typtype in ('e', 'd', 'c')
      and not exists (
        select 1
        from pg_class c
        where c.reltype = t.oid
          and c.relkind <> 'c'
      )
    order by t.typname
  loop
    v_sql := v_sql || public.admin_backup_acl_sql(
      r.typacl, 'T'::"char", r.typowner, r.target
    );
  end loop;

  v_sql := v_sql || E'\n-- Comments\n';
  for r in
    select format(
      'COMMENT ON TABLE %I.%I IS %L;',
      n.nspname,
      c.relname,
      d.description
    ) as stmt
    from pg_description d
    join pg_class c on c.oid = d.objoid
    join pg_namespace n on n.oid = c.relnamespace
    where d.classoid = 'pg_class'::regclass
      and d.objsubid = 0
      and n.nspname = 'public'
      and c.relkind in ('r', 'p', 'v', 'm')
    order by c.relname
  loop
    v_sql := v_sql || r.stmt || E'\n';
  end loop;

  for r in
    select format(
      'COMMENT ON COLUMN %I.%I.%I IS %L;',
      n.nspname,
      c.relname,
      a.attname,
      d.description
    ) as stmt
    from pg_description d
    join pg_class c on c.oid = d.objoid
    join pg_namespace n on n.oid = c.relnamespace
    join pg_attribute a
      on a.attrelid = c.oid
     and a.attnum = d.objsubid
    where d.classoid = 'pg_class'::regclass
      and d.objsubid > 0
      and n.nspname = 'public'
      and not a.attisdropped
    order by c.relname, a.attnum
  loop
    v_sql := v_sql || r.stmt || E'\n';
  end loop;

  for r in
    select format(
      'COMMENT ON FUNCTION %I.%I(%s) IS %L;',
      n.nspname,
      p.proname,
      pg_get_function_identity_arguments(p.oid),
      d.description
    ) as stmt
    from pg_description d
    join pg_proc p on p.oid = d.objoid
    join pg_namespace n on n.oid = p.pronamespace
    where d.classoid = 'pg_proc'::regclass
      and n.nspname = 'public'
      and p.prokind in ('f', 'w')
    order by p.proname
  loop
    v_sql := v_sql || r.stmt || E'\n';
  end loop;

  v_sql := v_sql || E'\n-- Realtime publication\n';
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    for r in
      select schemaname, tablename
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
      order by tablename
    loop
      v_sql := v_sql || format(
        E'DO $pub$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE %I.%I; EXCEPTION WHEN duplicate_object THEN NULL; END $pub$;\n',
        r.schemaname,
        r.tablename
      );
    end loop;
  end if;

  -- Reset script. Names are taken from the catalog at export time.
  v_reset := E'-- STOP. This deletes every object in the public schema, including rows.\n-- Run it only when rebuilding a project, then run schema_sql from the same file.\n-- It does not delete auth accounts.\n\n';

  for r in
    select format(
      'DROP TRIGGER IF EXISTS %I ON %I.%I;',
      t.tgname,
      n.nspname,
      c.relname
    ) as stmt
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    join pg_proc p on p.oid = t.tgfoid
    join pg_namespace pn on pn.oid = p.pronamespace
    where not t.tgisinternal
      and pn.nspname = 'public'
      and n.nspname <> 'public'
    order by n.nspname, c.relname, t.tgname
  loop
    v_reset := v_reset || r.stmt || E'\n';
  end loop;

  for r in
    select format(
      'DROP %s IF EXISTS public.%I CASCADE;',
      case c.relkind
        when 'v' then 'VIEW'
        when 'm' then 'MATERIALIZED VIEW'
        else 'TABLE'
      end,
      c.relname
    ) as stmt
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind in ('v', 'm', 'r', 'p')
    order by case c.relkind when 'v' then 0 when 'm' then 1 else 2 end, c.relname
  loop
    v_reset := v_reset || r.stmt || E'\n';
  end loop;

  for r in
    select format(
      'DROP %s IF EXISTS public.%I(%s) CASCADE;',
      case p.prokind
        when 'p' then 'PROCEDURE'
        when 'a' then 'AGGREGATE'
        else 'FUNCTION'
      end,
      p.proname,
      pg_get_function_identity_arguments(p.oid)
    ) as stmt
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and not exists (
        select 1
        from pg_depend d
        where d.objid = p.oid
          and d.deptype = 'e'
      )
    order by p.proname, p.oid
  loop
    v_reset := v_reset || r.stmt || E'\n';
  end loop;

  for r in
    select format('DROP SEQUENCE IF EXISTS public.%I CASCADE;', s.relname) as stmt
    from pg_class s
    join pg_namespace n on n.oid = s.relnamespace
    where n.nspname = 'public'
      and s.relkind = 'S'
    order by s.relname
  loop
    v_reset := v_reset || r.stmt || E'\n';
  end loop;

  for r in
    select format('DROP TYPE IF EXISTS public.%I CASCADE;', t.typname) as stmt
    from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'public'
      and (
        t.typtype in ('e', 'd')
        or (
          t.typtype = 'c'
          and exists (
            select 1
            from pg_class c
            where c.oid = t.typrelid
              and c.relkind = 'c'
          )
        )
      )
    order by t.typname
  loop
    v_reset := v_reset || r.stmt || E'\n';
  end loop;

  return jsonb_build_object(
    'schema_sql', v_sql,
    'reset_public_sql', v_reset
  );
end;
$$;

create or replace function public.admin_backup_rows(
  p_schema text,
  p_table text,
  p_offset integer default 0,
  p_limit integer default 40
) returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_schema text;
  v_rel regclass;
  v_order text;
  v_limit integer;
  v_offset integer;
  v_rows jsonb;
  v_full integer;
  v_done boolean;
begin
  perform public.admin_backup_guard();

  if p_table is null or p_table !~ '^[a-z_][a-z0-9_]*$' then
    raise exception 'Unknown table.';
  end if;

  if p_schema = 'public' then
    v_schema := 'public';
    if p_table in ('admin_restore_runs', 'admin_restore_staging') then
      raise exception 'Unknown table.';
    end if;
    select c.oid::regclass
    into v_rel
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = p_table
      and c.relkind in ('r', 'p');
  elsif p_schema = 'auth' then
    v_schema := 'auth';
    if p_table not in ('users', 'identities') then
      raise exception 'Unknown table.';
    end if;
    v_rel := format('auth.%I', p_table)::regclass;
  else
    raise exception 'Unknown schema.';
  end if;

  if v_rel is null then
    raise exception 'Unknown table.';
  end if;

  v_limit := least(greatest(coalesce(p_limit, 40), 1), 40);
  v_offset := greatest(coalesce(p_offset, 0), 0);
  v_order := public.admin_backup_order_by(v_rel);

  execute format(
    $q$
      with page as materialized (
        select *
        from %I.%I
        order by %s
        offset %s
        limit %s
      )
      select coalesce(jsonb_agg(line order by ord), '[]'::jsonb)
      from (
        select to_jsonb(page)::text as line, row_number() over () as ord
        from page
      ) numbered
    $q$,
    v_schema,
    p_table,
    v_order,
    v_offset,
    v_limit
  )
  into v_rows;

  v_full := jsonb_array_length(v_rows);
  while octet_length(v_rows::text) > 900000 and jsonb_array_length(v_rows) > 1 loop
    select coalesce(jsonb_agg(value order by ordinality), '[]'::jsonb)
    into v_rows
    from jsonb_array_elements(v_rows) with ordinality
    where ordinality <= greatest(jsonb_array_length(v_rows) / 2, 1);
  end loop;

  v_done := jsonb_array_length(v_rows) = v_full and v_full < v_limit;

  return jsonb_build_object('rows', v_rows, 'done', v_done);
end;
$$;

-- ---------------------------------------------------------------------------
-- Restore. Chunks sit in staging until commit, which is one transaction.
-- ---------------------------------------------------------------------------

create or replace function public.admin_restore_begin(
  p_confirm text,
  p_tables text[],
  p_restore_auth boolean
) returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_name text;
  v_tables text[];
  v_run uuid;
begin
  perform public.admin_backup_guard();

  if btrim(coalesce(p_confirm, '')) is distinct from 'RESTORE' then
    raise exception 'Type RESTORE to confirm.';
  end if;
  if p_tables is null or cardinality(p_tables) = 0 then
    raise exception 'The backup file has no tables.';
  end if;
  if cardinality(p_tables) > 500 then
    raise exception 'The backup file has too many tables.';
  end if;

  select coalesce(array_agg(t order by t), '{}')
  into v_tables
  from (select distinct unnest(p_tables) as t) as s
  where t is not null;

  foreach v_name in array v_tables loop
    if v_name !~ '^[a-z_][a-z0-9_]*$'
       or v_name in ('admin_restore_runs', 'admin_restore_staging')
       or not exists (
         select 1
         from pg_class c
         join pg_namespace n on n.oid = c.relnamespace
         where n.nspname = 'public'
           and c.relname = v_name
           and c.relkind in ('r', 'p')
       )
    then
      raise exception
        'This database has no table named %. Apply the backup schema SQL or the git migrations first.',
        v_name;
    end if;
  end loop;

  delete from public.admin_restore_runs
  where finished_at is null
    and (
      actor_id = auth.uid()
      or started_at < now() - interval '6 hours'
    );

  insert into public.admin_restore_runs (actor_id, restore_auth, tables)
  values (auth.uid(), coalesce(p_restore_auth, false), v_tables)
  returning id into v_run;

  perform public.admin_log_action(
    'backup_restore_started',
    null,
    jsonb_build_object(
      'tables', cardinality(v_tables),
      'auth', coalesce(p_restore_auth, false)
    )
  );

  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.admin_restore_stage(
  p_schema text,
  p_table text,
  p_rows jsonb
) returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_run uuid;
  v_tables text[];
  v_auth boolean;
  v_schema text;
begin
  perform public.admin_backup_guard();

  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    raise exception 'Backup rows must be a list.';
  end if;
  if jsonb_array_length(p_rows) > 40 then
    raise exception 'That chunk is too large.';
  end if;
  if octet_length(p_rows::text) > 1500000 then
    raise exception 'That chunk is too large.';
  end if;
  if p_table is null or p_table !~ '^[a-z_][a-z0-9_]*$' then
    raise exception 'Unknown table.';
  end if;

  select id, tables, restore_auth
  into v_run, v_tables, v_auth
  from public.admin_restore_runs
  where actor_id = auth.uid()
    and finished_at is null
    and started_at > now() - interval '6 hours'
  order by started_at desc
  limit 1;

  if v_run is null then
    raise exception 'Start the restore from the Backup page before uploading rows.';
  end if;

  if p_schema = 'public' then
    v_schema := 'public';
    if not (p_table = any (v_tables)) then
      raise exception 'That table is not part of this restore.';
    end if;
  elsif p_schema = 'auth' then
    v_schema := 'auth';
    if not v_auth or p_table not in ('users', 'identities') then
      raise exception 'That table is not part of this restore.';
    end if;
  else
    raise exception 'Unknown schema.';
  end if;

  insert into public.admin_restore_staging (run_id, schema_name, table_name, rows_data)
  values (v_run, v_schema, p_table, p_rows);

  return jsonb_build_object('staged', jsonb_array_length(p_rows));
end;
$$;

create or replace function public.admin_restore_commit()
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_run uuid;
  v_tables text[];
  v_auth boolean;
  v_actor uuid;
  v_missing text;
  v_list text;
  v_order text[];
  v_name text;
  v_rec record;
  v_seqs integer := 0;
begin
  perform public.admin_backup_guard();
  v_actor := auth.uid();

  select id, tables, restore_auth
  into v_run, v_tables, v_auth
  from public.admin_restore_runs
  where actor_id = v_actor
    and finished_at is null
  order by started_at desc
  limit 1;

  if v_run is null then
    raise exception 'Start the restore from the Backup page before applying it.';
  end if;

  select string_agg(t, ', ' order by t)
  into v_missing
  from unnest(v_tables) as t
  where not exists (
    select 1
    from public.admin_restore_staging s
    where s.run_id = v_run
      and s.schema_name = 'public'
      and s.table_name = t
  );

  if v_missing is not null then
    raise exception 'The upload did not finish, so nothing was changed. Missing: %', v_missing;
  end if;

  if v_auth then
    if not exists (
      select 1
      from public.admin_restore_staging
      where run_id = v_run
        and schema_name = 'auth'
        and table_name = 'users'
    ) or not exists (
      select 1
      from public.admin_restore_staging
      where run_id = v_run
        and schema_name = 'auth'
        and table_name = 'identities'
    ) then
      raise exception 'The upload did not finish, so nothing was changed.';
    end if;

    for v_name in
      select name
      from unnest(array['users', 'identities']::text[]) as name
    loop
      for v_rec in
        select s.rows_data
        from public.admin_restore_staging s
        where s.run_id = v_run
          and s.schema_name = 'auth'
          and s.table_name = v_name
        order by s.id
      loop
        perform public.admin_restore_auth_write(v_name, v_rec.rows_data);
      end loop;
    end loop;
  end if;

  select string_agg(format('%I.%I', 'public', t), ', ' order by t)
  into v_list
  from (select distinct unnest(v_tables) as t) as names;

  -- One statement so foreign keys between these tables do not block the wipe.
  -- Tables that reference them from outside this list make the statement fail,
  -- and the whole restore rolls back.
  execute 'truncate table ' || v_list || ' restart identity';

  select coalesce(array_agg(name order by ord), '{}')
  into v_order
  from unnest(public.admin_backup_load_order()) with ordinality as listed(name, ord)
  where name = any (v_tables);

  select v_order || coalesce(array_agg(t order by t), '{}')
  into v_order
  from unnest(v_tables) as t
  where not (t = any (v_order));

  foreach v_name in array v_order loop
    for v_rec in
      select s.rows_data
      from public.admin_restore_staging s
      where s.run_id = v_run
        and s.schema_name = 'public'
        and s.table_name = v_name
      order by s.id
    loop
      perform public.admin_restore_write(v_name, v_rec.rows_data);
    end loop;
  end loop;

  update public.profiles
  set is_admin = true
  where id = v_actor;

  if not found then
    raise exception
      'The backup has no profile for the account you are signed in as, so nothing was changed.';
  end if;

  for v_rec in
    select
      seq.oid::regclass as seq_name,
      parent.relname as tbl,
      a.attname as col
    from pg_class seq
    join pg_depend d
      on d.objid = seq.oid
     and d.deptype in ('a', 'i')
     and d.classid = 'pg_class'::regclass
    join pg_class parent on parent.oid = d.refobjid
    join pg_namespace n on n.oid = parent.relnamespace
    join pg_attribute a
      on a.attrelid = parent.oid
     and a.attnum = d.refobjsubid
    where seq.relkind = 'S'
      and n.nspname = 'public'
      and parent.relname = any (v_tables)
      and a.atttypid in ('int2'::regtype, 'int4'::regtype, 'int8'::regtype)
      and not a.attisdropped
  loop
    execute format(
      $q$
        select setval(
          %L::regclass,
          greatest(coalesce((select max(%I) from public.%I), 1), 1),
          (select max(%I) from public.%I) is not null
        )
      $q$,
      v_rec.seq_name::text,
      v_rec.col,
      v_rec.tbl,
      v_rec.col,
      v_rec.tbl
    );
    v_seqs := v_seqs + 1;
  end loop;

  delete from public.admin_restore_staging where run_id = v_run;

  update public.admin_restore_runs
  set finished_at = now()
  where id = v_run;

  perform public.admin_log_action(
    'backup_restore_finished',
    null,
    jsonb_build_object('tables', cardinality(v_tables), 'auth', v_auth, 'sequences', v_seqs)
  );

  return jsonb_build_object('ok', true, 'sequences', v_seqs);
end;
$$;

create or replace function public.admin_restore_cancel()
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
begin
  perform public.admin_backup_guard();

  delete from public.admin_restore_runs
  where actor_id = auth.uid()
    and finished_at is null;

  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.admin_backup_guard() from public, anon, authenticated, service_role;
revoke all on function public.admin_backup_load_order() from public, anon, authenticated, service_role;
revoke all on function public.admin_backup_order_by(regclass) from public, anon, authenticated, service_role;
revoke all on function public.admin_backup_acl_sql(aclitem[], "char", oid, text) from public, anon, authenticated, service_role;
revoke all on function public.admin_restore_write(text, jsonb) from public, anon, authenticated, service_role;
revoke all on function public.admin_restore_auth_write(text, jsonb) from public, anon, authenticated, service_role;

revoke all on function public.admin_backup_manifest() from public, anon;
revoke all on function public.admin_backup_schema() from public, anon;
revoke all on function public.admin_backup_rows(text, text, integer, integer) from public, anon;
revoke all on function public.admin_restore_begin(text, text[], boolean) from public, anon;
revoke all on function public.admin_restore_stage(text, text, jsonb) from public, anon;
revoke all on function public.admin_restore_commit() from public, anon;
revoke all on function public.admin_restore_cancel() from public, anon;

grant execute on function public.admin_backup_manifest() to authenticated;
grant execute on function public.admin_backup_schema() to authenticated;
grant execute on function public.admin_backup_rows(text, text, integer, integer) to authenticated;
grant execute on function public.admin_restore_begin(text, text[], boolean) to authenticated;
grant execute on function public.admin_restore_stage(text, text, jsonb) to authenticated;
grant execute on function public.admin_restore_commit() to authenticated;
grant execute on function public.admin_restore_cancel() to authenticated;

comment on function public.admin_backup_manifest() is
  'Admin only. Counts rows and lists tables for a local backup. Does not return row contents.';

comment on function public.admin_backup_schema() is
  'Admin only. SQL text for the public schema: types, tables, functions, triggers, policies, and grants.';

comment on function public.admin_backup_rows(text, text, integer, integer) is
  'Admin only. One page of backup rows as JSON text so large numbers are not rounded.';

comment on function public.admin_restore_begin(text, text[], boolean) is
  'Admin only. Opens a restore upload. Requires the confirm word RESTORE. Does not change live rows.';

comment on function public.admin_restore_stage(text, text, jsonb) is
  'Admin only. Stores one backup chunk until commit.';

comment on function public.admin_restore_commit() is
  'Admin only. Replaces staged tables in one transaction. Rolls back completely on failure.';

comment on function public.admin_restore_cancel() is
  'Admin only. Deletes an unfinished restore upload.';
