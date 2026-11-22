-- Selected-audience announcements and per-install push tokens.
--
-- audience = 'all' is the existing broadcast: every student sees the inbox
-- row, and the first publish alerts the FCM topic `broadcast`.
-- audience = 'selected' is an inbox row only for announcement_recipients,
-- and the alert goes to those accounts' push_tokens (not the topic).
--
-- The website Users page calls admin_search_users_filtered, then
-- admin_notify_users. The publish trigger already queues send-announcement-push.
-- Phones register a token with register_push_token while signed in.

alter table public.announcements
  add column if not exists audience text not null default 'all',
  add column if not exists created_by uuid references auth.users (id) on delete set null;

alter table public.announcements
  drop constraint if exists announcements_audience_check;

alter table public.announcements
  add constraint announcements_audience_check
  check (audience in ('all', 'selected'));

comment on column public.announcements.audience is
  'all: every signed-in student. selected: only announcement_recipients.';

comment on column public.announcements.created_by is
  'Admin who created the row, when the app or website saved it. Null for older rows and Table Editor inserts.';

comment on column public.announcements.push_sent_at is
  'Set when the one alert is claimed. Cleared if FCM accepts none of it. Null means it can still be sent.';

create table if not exists public.announcement_recipients (
  announcement_id uuid not null references public.announcements (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  primary key (announcement_id, user_id)
);

create index if not exists announcement_recipients_user_idx
  on public.announcement_recipients (user_id);

comment on table public.announcement_recipients is
  'Accounts that can read an announcement with audience = selected. Empty for broadcasts.';

create table if not exists public.push_tokens (
  token text primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  updated_at timestamptz not null default now(),
  constraint push_tokens_token_length check (char_length(token) between 20 and 4096)
);

create index if not exists push_tokens_user_id_idx
  on public.push_tokens (user_id);

comment on table public.push_tokens is
  'FCM registration tokens for targeted alerts. One token belongs to one account; signing in on that phone moves the row. Students have no direct access.';

alter table public.announcement_recipients enable row level security;
alter table public.push_tokens enable row level security;

drop policy if exists "own announcement recipient select" on public.announcement_recipients;
create policy "own announcement recipient select" on public.announcement_recipients
  for select
  to authenticated
  using (user_id = auth.uid());

revoke all on table public.announcement_recipients from public, anon, authenticated;
grant select on table public.announcement_recipients to authenticated;
grant all on table public.announcement_recipients to service_role;

revoke all on table public.push_tokens from public, anon, authenticated;
grant all on table public.push_tokens to service_role;

drop policy if exists "active announcements select" on public.announcements;
create policy "active announcements select" on public.announcements
  for select
  to authenticated
  using (
    is_active
    and (expires_at is null or expires_at > now())
    and (
      audience = 'all'
      or exists (
        select 1
        from public.announcement_recipients r
        where r.announcement_id = announcements.id
          and r.user_id = auth.uid()
      )
    )
  );

-- ---------------------------------------------------------------------------
-- Shared filter. Search and "everyone matching" both call this.
-- ---------------------------------------------------------------------------

create or replace function private.effective_plan_id(
  p_plan_id uuid,
  p_plan_suspended_at timestamptz,
  p_plan_expires_at timestamptz
) returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select case
    when p_plan_suspended_at is not null then free_plan.id
    when p_plan_expires_at is not null and p_plan_expires_at < now() then free_plan.id
    else p_plan_id
  end
  from (select id from public.plans where code = 'free' limit 1) free_plan;
$$;

comment on function private.effective_plan_id(uuid, timestamptz, timestamptz) is
  'Plan that gates the account. The free plan when suspended or past plan_expires_at.';

revoke all on function private.effective_plan_id(uuid, timestamptz, timestamptz)
  from public, anon, authenticated;

create or replace function private.normalize_user_filters(p_filters jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_query text;
  v_plan uuid;
  v_days text;
  v_days_int integer;
  v_blocked boolean;
begin
  if p_filters is null or jsonb_typeof(p_filters) <> 'object' then
    raise exception 'Filters must be an object.';
  end if;

  if not exists (select 1 from public.plans where code = 'free') then
    raise exception 'The free plan is missing.';
  end if;

  v_query := nullif(btrim(coalesce(p_filters->>'query', '')), '');
  if v_query is not null then
    v_query := nullif(replace(replace(v_query, '%', ''), '_', ''), '');
    if v_query is not null and char_length(v_query) > 80 then
      raise exception 'Search text must be 80 characters or less.';
    end if;
  end if;

  if nullif(btrim(coalesce(p_filters->>'plan_id', '')), '') is not null then
    begin
      v_plan := (p_filters->>'plan_id')::uuid;
    exception
      when invalid_text_representation then
        raise exception 'Choose a plan from the list.';
    end;
    if not exists (select 1 from public.plans where id = v_plan) then
      raise exception 'Choose a plan from the list.';
    end if;
  end if;

  if nullif(btrim(coalesce(p_filters->>'expires_within_days', '')), '') is not null then
    v_days := btrim(p_filters->>'expires_within_days');
    if v_days !~ '^[0-9]{1,3}$' then
      raise exception 'Expires within must be a whole number of days from 1 to 365.';
    end if;
    v_days_int := v_days::integer;
    if v_days_int < 1 or v_days_int > 365 then
      raise exception 'Expires within must be a whole number of days from 1 to 365.';
    end if;
  end if;

  begin
    v_blocked := coalesce((p_filters->>'include_blocked')::boolean, false);
  exception
    when invalid_text_representation then
      raise exception 'Include blocked must be true or false.';
  end;

  return jsonb_build_object(
    'query', v_query,
    'plan_id', v_plan,
    'expires_within_days', v_days_int,
    'include_blocked', v_blocked
  );
end;
$$;

comment on function private.normalize_user_filters(jsonb) is
  'Checks the website user filters and returns query, plan_id, expires_within_days, and include_blocked.';

revoke all on function private.normalize_user_filters(jsonb) from public, anon, authenticated;

create or replace function private.matching_user_ids(p_filters jsonb)
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select p.id
  from public.profiles p
  join auth.users u on u.id = p.id
  cross join (
    select id from public.plans where code = 'free' limit 1
  ) free_plan
  where (
    nullif(p_filters->>'query', '') is null
    or u.email ilike '%' || (p_filters->>'query') || '%'
    or u.phone ilike '%' || (p_filters->>'query') || '%'
    or p.full_name ilike '%' || (p_filters->>'query') || '%'
    or p.phone ilike '%' || (p_filters->>'query') || '%'
  )
  and (
    coalesce((p_filters->>'include_blocked')::boolean, false)
    or p.blocked_at is null
  )
  and (
    nullif(p_filters->>'plan_id', '') is null
    or private.effective_plan_id(p.plan_id, p.plan_suspended_at, p.plan_expires_at)
       = (p_filters->>'plan_id')::uuid
  )
  and (
    nullif(p_filters->>'expires_within_days', '') is null
    or (
      p.plan_suspended_at is null
      and p.plan_id is distinct from free_plan.id
      and p.plan_expires_at is not null
      and p.plan_expires_at >= now()
      and p.plan_expires_at < now()
        + make_interval(days => (p_filters->>'expires_within_days')::integer)
    )
  );
$$;

comment on function private.matching_user_ids(jsonb) is
  'Accounts matching normalized user filters. Expires-within is a paid plan that is still active.';

revoke all on function private.matching_user_ids(jsonb) from public, anon, authenticated;

create or replace function public.admin_search_users_filtered(p_filters jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_filters jsonb;
  v_limit integer := 100;
  v_offset integer := 0;
  v_total integer;
  v_users jsonb;
begin
  perform public.assert_admin();

  if p_filters is null or jsonb_typeof(p_filters) <> 'object' then
    raise exception 'Filters must be an object.';
  end if;

  if nullif(btrim(coalesce(p_filters->>'limit', '')), '') is not null then
    if btrim(p_filters->>'limit') !~ '^[0-9]{1,4}$' then
      raise exception 'Page size must be a whole number.';
    end if;
    v_limit := least(greatest(btrim(p_filters->>'limit')::integer, 1), 100);
  end if;

  if nullif(btrim(coalesce(p_filters->>'offset', '')), '') is not null then
    if btrim(p_filters->>'offset') !~ '^[0-9]{1,6}$' then
      raise exception 'Page offset must be a whole number.';
    end if;
    v_offset := least(btrim(p_filters->>'offset')::integer, 100000);
  end if;

  v_filters := private.normalize_user_filters(p_filters);

  select count(*)::int
  into v_total
  from private.matching_user_ids(v_filters) as matched(id);

  select coalesce(jsonb_agg(page.user_json order by page.created_at desc, page.id desc), '[]'::jsonb)
  into v_users
  from (
    select
      p.created_at,
      p.id,
      jsonb_build_object(
        'id', p.id,
        'full_name', p.full_name,
        'phone', coalesce(p.phone, u.phone),
        'plan_name', effective.name,
        'plan_expires_at', p.plan_expires_at,
        'blocked', p.blocked_at is not null
      ) as user_json
    from private.matching_user_ids(v_filters) as matched(id)
    join public.profiles p on p.id = matched.id
    join auth.users u on u.id = p.id
    join public.plans effective
      on effective.id = private.effective_plan_id(
        p.plan_id,
        p.plan_suspended_at,
        p.plan_expires_at
      )
    order by p.created_at desc, p.id desc
    limit v_limit
    offset v_offset
  ) page;

  return jsonb_build_object('total', v_total, 'users', v_users);
end;
$$;

comment on function public.admin_search_users_filtered(jsonb) is
  'Admin user search. Effective plan, expiry window, name or phone. Blocked accounts are hidden unless include_blocked is true. Page size is at most 100.';

revoke all on function public.admin_search_users_filtered(jsonb) from public, anon;
grant execute on function public.admin_search_users_filtered(jsonb) to authenticated;

create or replace function public.admin_notify_users(p_body jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_title text := nullif(btrim(coalesce(p_body->>'title', '')), '');
  v_body text := nullif(btrim(coalesce(p_body->>'body', '')), '');
  v_category text := lower(btrim(coalesce(p_body->>'category', 'general')));
  v_deep_link text := nullif(btrim(coalesce(p_body->>'deep_link', '')), '');
  v_has_ids boolean;
  v_has_filters boolean;
  v_ids uuid[];
  v_filters jsonb;
  v_id uuid;
  v_count integer;
begin
  perform public.assert_admin();

  if p_body is null or jsonb_typeof(p_body) <> 'object' then
    raise exception 'Send a notification object.';
  end if;
  if v_title is null then
    raise exception 'Title is required.';
  end if;
  if v_body is null then
    raise exception 'Body is required.';
  end if;
  if v_category not in ('general', 'version', 'offer', 'payment') then
    raise exception 'Category must be general, version, offer, or payment.';
  end if;
  if v_deep_link is not null and (
    v_deep_link !~ '^/[A-Za-z0-9/_?=&%-]*$'
    or v_deep_link ~ '^//'
    or v_deep_link ~ '^/admin(/|$)'
  ) then
    raise exception 'Deep link must be an in-app student path starting with /.';
  end if;

  v_has_ids := p_body ? 'user_ids' and jsonb_typeof(p_body->'user_ids') = 'array';
  v_has_filters := p_body ? 'filters' and jsonb_typeof(p_body->'filters') = 'object';

  if v_has_ids and v_has_filters then
    raise exception 'Pass either selected people or filters, not both.';
  end if;
  if not v_has_ids and not v_has_filters then
    raise exception 'Choose people or a filter before sending.';
  end if;

  if v_has_ids then
    if jsonb_array_length(p_body->'user_ids') > 500 then
      raise exception 'Select at most 500 people, or send to everyone matching the filters.';
    end if;
    if exists (
      select 1
      from jsonb_array_elements(p_body->'user_ids') as raw(value)
      where jsonb_typeof(raw.value) <> 'string'
         or raw.value #>> '{}' !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    ) then
      raise exception 'One of the selected accounts is not valid.';
    end if;

    select coalesce(array_agg(distinct picked.id), '{}')
    into v_ids
    from (
      select raw.value::uuid as id
      from jsonb_array_elements_text(p_body->'user_ids') as raw(value)
    ) picked
    join public.profiles p on p.id = picked.id;
  else
    v_filters := private.normalize_user_filters(p_body->'filters');
    select coalesce(array_agg(matched.id), '{}')
    into v_ids
    from (
      select id
      from private.matching_user_ids(v_filters)
      limit 2001
    ) matched;
  end if;

  v_count := coalesce(cardinality(v_ids), 0);
  if v_count = 0 then
    if v_has_ids then
      raise exception 'Select at least one person.';
    end if;
    raise exception 'No accounts match these filters.';
  end if;
  if not v_has_ids and v_count > 2000 then
    raise exception 'Narrow the filters. 2000 is the most one send can include.';
  end if;

  insert into public.announcements (
    title, body, category, deep_link, is_active, audience, published_at, created_by
  ) values (
    v_title, v_body, v_category, v_deep_link, true, 'selected', now(), auth.uid()
  )
  returning id into v_id;

  insert into public.announcement_recipients (announcement_id, user_id)
  select v_id, recipient_id
  from unnest(v_ids) as recipient_id;

  perform public.admin_log_action(
    'notify_users',
    v_id,
    jsonb_build_object(
      'recipient_count', v_count,
      'category', v_category
    )
  );

  return jsonb_build_object(
    'id', v_id,
    'recipient_count', v_count,
    'queued', true
  );
end;
$$;

comment on function public.admin_notify_users(jsonb) is
  'Publishes one selected-audience announcement. Pass user_ids (at most 500) or filters (at most 2000 matches), not both. The publish trigger queues the phone alert.';

revoke all on function public.admin_notify_users(jsonb) from public, anon;
grant execute on function public.admin_notify_users(jsonb) to authenticated;

-- Tokens for the edge function. Not granted to students.
create or replace function public.announcement_push_tokens(p_announcement_id uuid)
returns table (token text)
language sql
stable
security definer
set search_path = public
as $$
  select t.token
  from public.announcement_recipients r
  join public.push_tokens t on t.user_id = r.user_id
  where r.announcement_id = p_announcement_id;
$$;

comment on function public.announcement_push_tokens(uuid) is
  'FCM tokens for a selected announcement. service_role only.';

revoke all on function public.announcement_push_tokens(uuid) from public, anon, authenticated;
grant execute on function public.announcement_push_tokens(uuid) to service_role;

create or replace function public.register_push_token(p_token text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_token text := nullif(btrim(coalesce(p_token, '')), '');
begin
  if auth.uid() is null then
    raise exception 'Not signed in.';
  end if;
  if v_token is null
     or char_length(v_token) < 20
     or char_length(v_token) > 4096
     or v_token ~ '\s' then
    raise exception 'That notification token is not valid.';
  end if;

  insert into public.push_tokens (token, user_id, updated_at)
  values (v_token, auth.uid(), now())
  on conflict (token) do update
    set user_id = excluded.user_id,
        updated_at = excluded.updated_at;
end;
$$;

comment on function public.register_push_token(text) is
  'Saves this install''s FCM token for the signed-in account. The same token moves if another account signs in on the phone.';

revoke all on function public.register_push_token(text) from public, anon;
grant execute on function public.register_push_token(text) to authenticated;

create or replace function public.unregister_push_token(p_token text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_token text := nullif(btrim(coalesce(p_token, '')), '');
begin
  if auth.uid() is null then
    raise exception 'Not signed in.';
  end if;
  if v_token is null then
    return;
  end if;

  delete from public.push_tokens
  where token = v_token
    and user_id = auth.uid();
end;
$$;

comment on function public.unregister_push_token(text) is
  'Removes this install''s FCM token while the account is still signed in.';

revoke all on function public.unregister_push_token(text) from public, anon;
grant execute on function public.unregister_push_token(text) to authenticated;

-- ---------------------------------------------------------------------------
-- List and upsert learn about audience. Upsert cannot retarget a send.
-- ---------------------------------------------------------------------------

create or replace function public.admin_list_announcements()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.assert_admin();

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', a.id,
      'title', a.title,
      'body', a.body,
      'category', a.category,
      'deep_link', a.deep_link,
      'is_active', a.is_active,
      'audience', a.audience,
      'recipient_count', (
        select count(*)::int
        from public.announcement_recipients r
        where r.announcement_id = a.id
      ),
      'published_at', a.published_at,
      'expires_at', a.expires_at,
      'created_at', a.created_at
    ) order by a.published_at desc)
    from public.announcements a
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.admin_list_announcements() from public, anon;
grant execute on function public.admin_list_announcements() to authenticated;

create or replace function public.admin_upsert_announcement(p_body jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid := nullif(p_body->>'id', '')::uuid;
  v_title text := nullif(btrim(coalesce(p_body->>'title', '')), '');
  v_body text := nullif(btrim(coalesce(p_body->>'body', '')), '');
  v_category text := lower(btrim(coalesce(p_body->>'category', 'general')));
  v_deep_link text := nullif(btrim(coalesce(p_body->>'deep_link', '')), '');
  v_active boolean := coalesce((p_body->>'is_active')::boolean, false);
  v_expires timestamptz := nullif(p_body->>'expires_at', '')::timestamptz;
  v_was_active boolean;
begin
  perform public.assert_admin();

  if v_title is null then
    raise exception 'Title is required.';
  end if;
  if v_body is null then
    raise exception 'Body is required.';
  end if;
  if v_category not in ('general', 'version', 'offer', 'payment') then
    raise exception 'Category must be general, version, offer, or payment.';
  end if;
  if v_deep_link is not null and (
    v_deep_link !~ '^/[A-Za-z0-9/_?=&%-]*$'
    or v_deep_link ~ '^//'
    or v_deep_link ~ '^/admin(/|$)'
  ) then
    raise exception 'Deep link must be an in-app student path starting with /.';
  end if;

  if v_id is null then
    insert into public.announcements (
      title, body, category, deep_link, is_active, audience,
      published_at, expires_at, created_by
    ) values (
      v_title, v_body, v_category, v_deep_link, v_active, 'all',
      now(), v_expires, auth.uid()
    )
    returning id into v_id;
  else
    select is_active into v_was_active
    from public.announcements
    where id = v_id;

    if v_was_active is null then
      raise exception 'Announcement not found.';
    end if;

    -- audience and recipients stay as they are. A selected send cannot
    -- become a broadcast from this form.
    update public.announcements
    set
      title = v_title,
      body = v_body,
      category = v_category,
      deep_link = v_deep_link,
      is_active = v_active,
      expires_at = v_expires,
      published_at = case
        when v_active and not v_was_active then now()
        else published_at
      end
    where id = v_id;
  end if;

  perform public.admin_log_action(
    'upsert_announcement',
    v_id,
    jsonb_build_object('is_active', v_active, 'category', v_category)
  );

  return (
    select jsonb_build_object(
      'id', a.id,
      'title', a.title,
      'body', a.body,
      'category', a.category,
      'deep_link', a.deep_link,
      'is_active', a.is_active,
      'audience', a.audience,
      'recipient_count', (
        select count(*)::int
        from public.announcement_recipients r
        where r.announcement_id = a.id
      ),
      'published_at', a.published_at,
      'expires_at', a.expires_at,
      'created_at', a.created_at
    )
    from public.announcements a
    where a.id = v_id
  );
end;
$$;

revoke all on function public.admin_upsert_announcement(jsonb) from public, anon;
grant execute on function public.admin_upsert_announcement(jsonb) to authenticated;
