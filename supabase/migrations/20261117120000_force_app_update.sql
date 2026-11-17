-- Minimum Android build that may open the app. 0 means every install is allowed.
-- Students read it before sign-in (anon). Only an admin can change it.
-- The Play Store link stays in the app so this row cannot point at another store.

create table if not exists public.app_update_policy (
  id smallint primary key default 1 check (id = 1),
  min_version_code integer not null default 0,
  min_version_name text not null default '',
  updated_at timestamptz not null default now(),
  constraint app_update_policy_code_range check (
    min_version_code >= 0 and min_version_code <= 2100000000
  ),
  constraint app_update_policy_name_length check (char_length(min_version_name) <= 40)
);

comment on table public.app_update_policy is
  'One row. min_version_code is the lowest Android versionCode that may open the app. 0 allows every build. min_version_name is the label shown on the update screen.';

insert into public.app_update_policy (id)
values (1)
on conflict (id) do nothing;

alter table public.app_update_policy enable row level security;

revoke all on table public.app_update_policy from public, anon, authenticated;
grant all on table public.app_update_policy to service_role;

-- ---------------------------------------------------------------------------
-- Read (anon + signed-in). The gate runs before login.
-- ---------------------------------------------------------------------------

create or replace function public.app_update_policy()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (
      select jsonb_build_object(
        'min_version_code', p.min_version_code,
        'min_version_name', p.min_version_name,
        'updated_at', p.updated_at
      )
      from public.app_update_policy p
      where p.id = 1
    ),
    jsonb_build_object(
      'min_version_code', 0,
      'min_version_name', '',
      'updated_at', null
    )
  );
$$;

comment on function public.app_update_policy() is
  'Public minimum-build rule. No secrets. The app blocks Android installs below min_version_code.';

revoke all on function public.app_update_policy() from public;
grant execute on function public.app_update_policy() to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Write (admin)
-- ---------------------------------------------------------------------------

create or replace function public.admin_set_app_update_policy(
  p_min_version_code integer,
  p_min_version_name text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text := btrim(coalesce(p_min_version_name, ''));
begin
  perform public.assert_admin();

  if p_min_version_code is null
    or p_min_version_code < 0
    or p_min_version_code > 2100000000
  then
    raise exception 'Build number must be from 0 to 2100000000. Use 0 to allow every version.';
  end if;

  if v_name <> '' and v_name !~ '^[0-9A-Za-z][-0-9A-Za-z.+ ]{0,39}$' then
    raise exception 'Version name can use letters, numbers, dots, and hyphens.';
  end if;

  insert into public.app_update_policy (
    id, min_version_code, min_version_name, updated_at
  ) values (
    1, p_min_version_code, v_name, now()
  )
  on conflict (id) do update
  set
    min_version_code = excluded.min_version_code,
    min_version_name = excluded.min_version_name,
    updated_at = now();

  perform public.admin_log_action(
    'set_app_update_policy',
    null,
    jsonb_build_object(
      'min_version_code', p_min_version_code,
      'min_version_name', v_name
    )
  );

  return public.app_update_policy();
end;
$$;

comment on function public.admin_set_app_update_policy(integer, text) is
  'Admin sets the minimum Android versionCode. 0 turns the lock off.';

revoke all on function public.admin_set_app_update_policy(integer, text) from public, anon;
grant execute on function public.admin_set_app_update_policy(integer, text) to authenticated;
