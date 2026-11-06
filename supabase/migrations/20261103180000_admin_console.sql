-- In-app admin. Students keep the same login. profiles.is_admin is set in the
-- SQL editor and is not in the authenticated UPDATE grant. Mutations go through
-- security definer RPCs that call assert_admin(). Password, email, and ban use
-- the admin-user-auth Edge Function because GoTrue is not reachable from SQL
-- the client can call. Question saves also queue sheet_outbox so Apps Script
-- can pull them into the Questions tab before the next sync_content_csv.

-- ---------------------------------------------------------------------------
-- profiles: operator flag + block (distinct from multi-device suspension)
-- ---------------------------------------------------------------------------

alter table public.profiles
  add column if not exists is_admin boolean not null default false,
  add column if not exists blocked_at timestamptz,
  add column if not exists blocked_reason text;

comment on column public.profiles.is_admin is
  'Operator account. Set only in the SQL editor. Omitted from the authenticated UPDATE grant.';

comment on column public.profiles.blocked_at is
  'When set, the auth user is banned. Distinct from plan_suspended_at (3rd device).';

revoke update on table public.profiles from authenticated;
grant update (
  full_name,
  phone,
  university_id,
  college_id,
  batch_year,
  mbbs_phase_id,
  onboarding_completed_at
) on table public.profiles to authenticated;

-- ---------------------------------------------------------------------------
-- Audit + sheet outbox (no client table privileges)
-- ---------------------------------------------------------------------------

create table if not exists public.admin_audit_log (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid not null references auth.users (id),
  action text not null,
  target_id uuid,
  detail jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_admin_audit_log_created
  on public.admin_audit_log (created_at desc);

comment on table public.admin_audit_log is
  'Who changed a user, plan, question, or announcement. Never store a password.';

create table if not exists public.sheet_outbox (
  id uuid primary key default gen_random_uuid(),
  question_id uuid references public.questions (id) on delete cascade,
  op text not null check (op in ('upsert', 'delete')),
  match_key jsonb,
  row_payload jsonb,
  created_at timestamptz not null default now(),
  applied_at timestamptz,
  constraint sheet_outbox_shape check (
    (op = 'delete' and match_key is not null)
    or (op = 'upsert' and row_payload is not null)
  )
);

create index if not exists idx_sheet_outbox_pending
  on public.sheet_outbox (created_at)
  where applied_at is null;

comment on table public.sheet_outbox is
  'App edits waiting for Apps Script to write the Questions tab. service_role only.';

alter table public.admin_audit_log enable row level security;
alter table public.sheet_outbox enable row level security;

revoke all on table public.admin_audit_log from public, anon, authenticated;
revoke all on table public.sheet_outbox from public, anon, authenticated;
grant all on table public.admin_audit_log to service_role;
grant all on table public.sheet_outbox to service_role;

-- ---------------------------------------------------------------------------
-- assert_admin + audit
-- ---------------------------------------------------------------------------

create or replace function public.assert_admin()
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Sign in to continue.';
  end if;

  if not exists (
    select 1
    from public.profiles
    where id = auth.uid()
      and is_admin
  ) then
    raise exception 'Admin only.';
  end if;
end;
$$;

comment on function public.assert_admin() is
  'Raises unless the signed-in profile has is_admin. Every admin RPC calls this.';

create or replace function public.admin_log_action(
  p_action text,
  p_target_id uuid,
  p_detail jsonb default '{}'::jsonb
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_detail jsonb := coalesce(p_detail, '{}'::jsonb);
begin
  perform public.assert_admin();

  if nullif(btrim(coalesce(p_action, '')), '') is null then
    raise exception 'Missing audit action.';
  end if;

  -- A client must not be able to persist a password by stuffing it in detail.
  v_detail := v_detail - 'password' - 'new_password';

  insert into public.admin_audit_log (actor_id, action, target_id, detail)
  values (auth.uid(), btrim(p_action), p_target_id, v_detail);
end;
$$;

comment on function public.admin_log_action(text, uuid, jsonb) is
  'Writes admin_audit_log. Strips password keys from detail.';

revoke all on function public.assert_admin() from public, anon;
revoke all on function public.admin_log_action(text, uuid, jsonb) from public, anon;
grant execute on function public.assert_admin() to authenticated;
grant execute on function public.admin_log_action(text, uuid, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- Admins are exempt from the 3-device lock (support must not be kicked)
-- ---------------------------------------------------------------------------

create or replace function public.claim_active_device(p_device_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_device text := nullif(btrim(p_device_id), '');
  v_was_known boolean;
  v_distinct int;
  v_suspended boolean;
  v_was_suspended boolean;
  v_just_suspended boolean := false;
  v_session_id uuid;
begin
  if v_uid is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  if v_device is null or char_length(v_device) > 128 then
    raise exception 'INVALID_DEVICE_ID';
  end if;

  if exists (
    select 1 from public.profiles where id = v_uid and is_admin
  ) then
    return jsonb_build_object(
      'ok', true,
      'suspended', false,
      'just_suspended', false,
      'distinct_device_count', 0
    );
  end if;

  select plan_suspended_at is not null
  into v_was_suspended
  from public.profiles
  where id = v_uid;

  select exists (
    select 1
    from public.device_claims
    where user_id = v_uid
      and device_id = v_device
  )
  into v_was_known;

  if v_was_known then
    update public.device_claims
    set last_seen_at = now()
    where user_id = v_uid
      and device_id = v_device;
  else
    insert into public.device_claims (user_id, device_id, first_seen_at, last_seen_at)
    values (v_uid, v_device, now(), now());
  end if;

  select count(*)::int
  into v_distinct
  from public.device_claims
  where user_id = v_uid;

  if not v_was_known and v_distinct > 2 then
    update public.profiles
    set
      plan_suspended_at = coalesce(plan_suspended_at, now()),
      plan_suspend_reason = coalesce(plan_suspend_reason, 'multi_device'),
      active_device_id = v_device,
      active_device_claimed_at = now()
    where id = v_uid;

    v_just_suspended := not coalesce(v_was_suspended, false);
  else
    update public.profiles
    set
      active_device_id = v_device,
      active_device_claimed_at = now()
    where id = v_uid;
  end if;

  select plan_suspended_at is not null
  into v_suspended
  from public.profiles
  where id = v_uid;

  begin
    v_session_id := nullif(auth.jwt() ->> 'session_id', '')::uuid;
  exception
    when others then
      v_session_id := null;
  end;

  if v_session_id is not null then
    delete from auth.sessions
    where user_id = v_uid
      and id is distinct from v_session_id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'suspended', coalesce(v_suspended, false),
    'just_suspended', v_just_suspended,
    'distinct_device_count', v_distinct
  );
end;
$$;

create or replace function public.assert_active_device(p_device_id text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_device text := nullif(btrim(p_device_id), '');
  v_active text;
begin
  if v_uid is null then
    return false;
  end if;

  if exists (
    select 1 from public.profiles where id = v_uid and is_admin
  ) then
    return true;
  end if;

  if v_device is null or char_length(v_device) > 128 then
    return false;
  end if;

  select active_device_id
  into v_active
  from public.profiles
  where id = v_uid;

  if v_active is null then
    return true;
  end if;

  return v_active = v_device;
end;
$$;

comment on function public.claim_active_device(text) is
  'Binds this install as the sole active device. Admins are exempt. Suspends plan on the 3rd unique device.';

comment on function public.assert_active_device(text) is
  'True if this install owns the account, or the account is an admin.';

grant execute on function public.claim_active_device(text) to authenticated;
grant execute on function public.assert_active_device(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Session revoke for block (Edge Function / service_role only)
-- ---------------------------------------------------------------------------

create or replace function public.admin_revoke_sessions(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_user_id is null then
    raise exception 'User not found.';
  end if;

  delete from auth.sessions where user_id = p_user_id;
end;
$$;

comment on function public.admin_revoke_sessions(uuid) is
  'Deletes GoTrue sessions for a blocked user. service_role only.';

revoke all on function public.admin_revoke_sessions(uuid) from public, anon, authenticated;
grant execute on function public.admin_revoke_sessions(uuid) to service_role;

-- ---------------------------------------------------------------------------
-- Users, plans, block flag
-- ---------------------------------------------------------------------------

create or replace function public.admin_user_json(p_user_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'id', p.id,
    'email', u.email,
    'full_name', p.full_name,
    'phone', p.phone,
    'plan', p.plan,
    'plan_expires_at', p.plan_expires_at,
    'plan_suspended_at', p.plan_suspended_at,
    'blocked_at', p.blocked_at,
    'blocked_reason', p.blocked_reason,
    'university_id', p.university_id,
    'university_name', uni.name,
    'college_id', p.college_id,
    'college_name', col.name,
    'batch_year', p.batch_year,
    'mbbs_phase_id', p.mbbs_phase_id,
    'is_admin', p.is_admin,
    'created_at', p.created_at
  )
  from public.profiles p
  join auth.users u on u.id = p.id
  left join public.universities uni on uni.id = p.university_id
  left join public.colleges col on col.id = p.college_id
  where p.id = p_user_id;
$$;

create or replace function public.admin_search_users(p_query text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_query text := nullif(btrim(coalesce(p_query, '')), '');
begin
  perform public.assert_admin();

  if v_query is not null then
    v_query := replace(replace(v_query, '%', ''), '_', '');
  end if;

  return coalesce((
    select jsonb_agg(public.admin_user_json(p.id) order by p.created_at desc)
    from (
      select p.id, p.created_at
      from public.profiles p
      join auth.users u on u.id = p.id
      where v_query is null
        or u.email ilike '%' || v_query || '%'
        or p.full_name ilike '%' || v_query || '%'
        or p.phone ilike '%' || v_query || '%'
      order by p.created_at desc
      limit 40
    ) p
  ), '[]'::jsonb);
end;
$$;

create or replace function public.admin_get_user(p_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_row jsonb;
begin
  perform public.assert_admin();

  v_row := public.admin_user_json(p_user_id);
  if v_row is null then
    raise exception 'User not found.';
  end if;

  return v_row;
end;
$$;

create or replace function public.admin_update_profile(
  p_user_id uuid,
  p_full_name text,
  p_phone text,
  p_university_id uuid,
  p_college_id uuid,
  p_batch_year int,
  p_mbbs_phase_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text := nullif(btrim(coalesce(p_full_name, '')), '');
  v_phone text := nullif(btrim(coalesce(p_phone, '')), '');
begin
  perform public.assert_admin();

  if not exists (select 1 from public.profiles where id = p_user_id) then
    raise exception 'User not found.';
  end if;

  if p_university_id is not null and not exists (
    select 1 from public.universities where id = p_university_id
  ) then
    raise exception 'Choose a university that already exists.';
  end if;

  if p_college_id is not null then
    if p_university_id is null or not exists (
      select 1
      from public.colleges
      where id = p_college_id
        and university_id = p_university_id
    ) then
      raise exception 'That college is not in this university.';
    end if;
  end if;

  if p_mbbs_phase_id is not null and not exists (
    select 1 from public.mbbs_phases where id = p_mbbs_phase_id
  ) then
    raise exception 'Choose a year of MBBS that already exists.';
  end if;

  if p_batch_year is not null and p_batch_year not between 1990 and 2100 then
    raise exception 'Batch year must be between 1990 and 2100.';
  end if;

  update public.profiles
  set
    full_name = v_name,
    phone = v_phone,
    university_id = p_university_id,
    college_id = p_college_id,
    batch_year = p_batch_year,
    mbbs_phase_id = p_mbbs_phase_id
  where id = p_user_id;

  perform public.admin_log_action(
    'update_profile',
    p_user_id,
    jsonb_build_object('full_name', v_name)
  );

  return public.admin_user_json(p_user_id);
end;
$$;

create or replace function public.admin_set_plan(
  p_user_id uuid,
  p_plan text,
  p_expires_at timestamptz
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_plan text := lower(btrim(coalesce(p_plan, '')));
begin
  perform public.assert_admin();

  if not exists (select 1 from public.profiles where id = p_user_id) then
    raise exception 'User not found.';
  end if;

  if v_plan not in ('free', 'pro', 'elite') then
    raise exception 'Pick a plan of free, pro, or elite.';
  end if;

  -- Direct write. Does not insert a payment row.
  update public.profiles
  set
    plan = v_plan::public.plan_tier,
    plan_started_at = now(),
    plan_expires_at = p_expires_at
  where id = p_user_id;

  perform public.admin_log_action(
    'set_plan',
    p_user_id,
    jsonb_build_object('plan', v_plan, 'plan_expires_at', p_expires_at)
  );

  return public.admin_user_json(p_user_id);
end;
$$;

create or replace function public.admin_clear_device_suspension(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.assert_admin();

  if not exists (select 1 from public.profiles where id = p_user_id) then
    raise exception 'User not found.';
  end if;

  update public.profiles
  set
    plan_suspended_at = null,
    plan_suspend_reason = null
  where id = p_user_id;

  perform public.admin_log_action('clear_device_suspension', p_user_id, '{}'::jsonb);

  return public.admin_user_json(p_user_id);
end;
$$;

create or replace function public.admin_set_blocked(
  p_user_id uuid,
  p_blocked boolean,
  p_reason text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.assert_admin();

  if p_user_id is null or not exists (
    select 1 from public.profiles where id = p_user_id
  ) then
    raise exception 'User not found.';
  end if;

  if p_user_id = auth.uid() and coalesce(p_blocked, false) then
    raise exception 'You cannot block your own account.';
  end if;

  if coalesce(p_blocked, false) then
    update public.profiles
    set
      blocked_at = coalesce(blocked_at, now()),
      blocked_reason = nullif(btrim(coalesce(p_reason, '')), '')
    where id = p_user_id;
  else
    update public.profiles
    set
      blocked_at = null,
      blocked_reason = null
    where id = p_user_id;
  end if;

  perform public.admin_log_action(
    case when coalesce(p_blocked, false) then 'block_user' else 'unblock_user' end,
    p_user_id,
    jsonb_build_object('reason', nullif(btrim(coalesce(p_reason, '')), ''))
  );

  return public.admin_user_json(p_user_id);
end;
$$;

revoke all on function public.admin_user_json(uuid) from public, anon, authenticated;
revoke all on function public.admin_search_users(text) from public, anon;
revoke all on function public.admin_get_user(uuid) from public, anon;
revoke all on function public.admin_update_profile(uuid, text, text, uuid, uuid, int, uuid) from public, anon;
revoke all on function public.admin_set_plan(uuid, text, timestamptz) from public, anon;
revoke all on function public.admin_clear_device_suspension(uuid) from public, anon;
revoke all on function public.admin_set_blocked(uuid, boolean, text) from public, anon;

grant execute on function public.admin_search_users(text) to authenticated;
grant execute on function public.admin_get_user(uuid) to authenticated;
grant execute on function public.admin_update_profile(uuid, text, text, uuid, uuid, int, uuid) to authenticated;
grant execute on function public.admin_set_plan(uuid, text, timestamptz) to authenticated;
grant execute on function public.admin_clear_device_suspension(uuid) to authenticated;
grant execute on function public.admin_set_blocked(uuid, boolean, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Announcements (admins can see drafts; students still use the RLS select)
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
      'published_at', a.published_at,
      'expires_at', a.expires_at,
      'created_at', a.created_at
    ) order by a.published_at desc)
    from public.announcements a
  ), '[]'::jsonb);
end;
$$;

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

  if v_id is null then
    insert into public.announcements (
      title, body, category, deep_link, is_active, published_at, expires_at
    ) values (
      v_title, v_body, v_category, v_deep_link, v_active, now(), v_expires
    )
    returning id into v_id;
  else
    select is_active into v_was_active
    from public.announcements
    where id = v_id;

    if v_was_active is null then
      raise exception 'Announcement not found.';
    end if;

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
      'published_at', a.published_at,
      'expires_at', a.expires_at,
      'created_at', a.created_at
    )
    from public.announcements a
    where a.id = v_id
  );
end;
$$;

revoke all on function public.admin_list_announcements() from public, anon;
revoke all on function public.admin_upsert_announcement(jsonb) from public, anon;
grant execute on function public.admin_list_announcements() to authenticated;
grant execute on function public.admin_upsert_announcement(jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- Question sheet identity (same formula as sync_content_csv)
-- ---------------------------------------------------------------------------

create or replace function public.admin_question_external_id(
  p_subject text,
  p_kind text,
  p_stem text
) returns text
language sql
immutable
as $$
  select 'CSV-' || upper(substr(md5(
    lower(regexp_replace(btrim(coalesce(p_subject, '')), '\s+', ' ', 'g')) || '|' ||
    coalesce(p_kind, '') || '|' ||
    lower(regexp_replace(btrim(coalesce(p_stem, '')), '\s+', ' ', 'g'))
  ), 1, 24));
$$;

create or replace function public.admin_paper_external_id(
  p_university_id uuid,
  p_college_id uuid,
  p_subject_id uuid,
  p_exam_type text,
  p_exam_year int,
  p_exam_month int,
  p_paper_name text
) returns text
language sql
immutable
as $$
  select 'CSV-EP-' || upper(substr(md5(
    p_university_id::text || '|' ||
    coalesce(p_college_id::text, '') || '|' ||
    p_subject_id::text || '|' ||
    coalesce(p_exam_type, '') || '|' ||
    p_exam_year::text || '|' ||
    p_exam_month::text || '|' ||
    lower(coalesce(p_paper_name, ''))
  ), 1, 24));
$$;

create or replace function public.admin_exam_type_label(p_exam_type text)
returns text
language sql
immutable
as $$
  select case p_exam_type
    when 'prof' then 'PROF'
    when 'supply' then 'SUPPLY'
    when 'pre_prof' then 'PRE PROF'
    when 'internal' then 'INTERNAL'
    else null
  end;
$$;

create or replace function public.admin_month_name(p_month int)
returns text
language sql
immutable
as $$
  select case p_month
    when 1 then 'January'
    when 2 then 'February'
    when 3 then 'March'
    when 4 then 'April'
    when 5 then 'May'
    when 6 then 'June'
    when 7 then 'July'
    when 8 then 'August'
    when 9 then 'September'
    when 10 then 'October'
    when 11 then 'November'
    when 12 then 'December'
    else null
  end;
$$;

-- Sheet row for one sitting, from the database after the save.
create or replace function public.admin_sheet_row(
  p_question_id uuid,
  p_exam_paper_id uuid
) returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'university_alias', u.code,
    'university_name', u.name,
    'college_alias', coalesce(c.short_form, ''),
    'college_name', coalesce(c.name, ''),
    'exam_type', coalesce(public.admin_exam_type_label(ep.exam_type), ''),
    'year', ep.exam_year::text,
    'month', coalesce(public.admin_month_name(ep.exam_month::int), ''),
    'paper_number', coalesce(ep.paper_name, ''),
    'subject_name', s.name,
    'chapter_name', coalesce(top.name, ''),
    'topic_name', coalesce(les.name, ''),
    'question_type', q.kind::text,
    'marks', case
      when q.marks is null then ''
      else regexp_replace(trim(to_char(q.marks, 'FM999990.99')), '\.$', '')
    end,
    'question_text', q.question_text,
    'option_a', coalesce(q.option_a, ''),
    'option_b', coalesce(q.option_b, ''),
    'option_c', coalesce(q.option_c, ''),
    'option_d', coalesce(q.option_d, ''),
    'correct_option', coalesce(q.correct_option, ''),
    'answers', coalesce(sa.body, ''),
    'exp_1', coalesce(q.explanation_text, ''),
    'exp_2', coalesce(q.explanation_deep, ''),
    'difficulty', q.difficulty::text,
    'required_plan', q.required_plan::text,
    'is_active', case when q.is_active then 'TRUE' else 'FALSE' end,
    'state', coalesce(u.state, '')
  )
  from public.questions q
  join public.exam_papers ep on ep.id = p_exam_paper_id
  join public.universities u on u.id = ep.university_id
  join public.subjects s on s.id = ep.subject_id
  left join public.colleges c on c.id = ep.college_id
  left join public.topics top on top.id = q.topic_id
  left join public.lessons les on les.id = q.lesson_id
  left join public.question_sample_answers sa on sa.question_id = q.id
  where q.id = p_question_id;
$$;

-- Identity Apps Script uses to find the existing Questions row.
create or replace function public.admin_sheet_match(
  p_subject text,
  p_kind text,
  p_stem text,
  p_exam_paper_id uuid
) returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'subject_name', p_subject,
    'question_type', p_kind,
    'question_text', p_stem,
    'university_alias', u.code,
    'college_alias', coalesce(c.short_form, ''),
    'exam_type', coalesce(public.admin_exam_type_label(ep.exam_type), ''),
    'year', ep.exam_year::text,
    'month', coalesce(public.admin_month_name(ep.exam_month::int), ''),
    'paper_number', coalesce(ep.paper_name, '')
  )
  from public.exam_papers ep
  join public.universities u on u.id = ep.university_id
  left join public.colleges c on c.id = ep.college_id
  where ep.id = p_exam_paper_id;
$$;

create or replace function public.admin_enqueue_sheet(
  p_question_id uuid,
  p_exam_paper_id uuid,
  p_op text,
  p_match jsonb
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row jsonb;
begin
  if p_op = 'upsert' then
    v_row := public.admin_sheet_row(p_question_id, p_exam_paper_id);
    if v_row is null then
      raise exception 'Could not build the sheet row for this question.';
    end if;
  elsif p_match is null then
    raise exception 'A delete needs the previous sheet identity.';
  end if;

  insert into public.sheet_outbox (question_id, op, match_key, row_payload)
  values (
    p_question_id,
    p_op,
    p_match,
    case when p_op = 'upsert' then v_row else null end
  );
end;
$$;

create or replace function public.admin_validate_sitting(
  p_university_id uuid,
  p_college_id uuid,
  p_subject_id uuid,
  p_exam_year int,
  p_exam_month int,
  p_exam_type text
) returns void
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if p_subject_id is null or not exists (
    select 1 from public.subjects where id = p_subject_id
  ) then
    raise exception 'Choose a subject that already exists.';
  end if;

  if p_university_id is null or not exists (
    select 1 from public.universities where id = p_university_id
  ) then
    raise exception 'Choose a university that already exists.';
  end if;

  if p_college_id is not null and not exists (
    select 1
    from public.colleges
    where id = p_college_id
      and university_id = p_university_id
  ) then
    raise exception 'That college is not in this university.';
  end if;

  if p_exam_type is null or p_exam_type not in ('prof', 'supply', 'pre_prof', 'internal') then
    raise exception 'Exam type must be prof, supply, pre_prof, or internal.';
  end if;

  if p_exam_year is null or p_exam_year not between 1990 and 2100 then
    raise exception 'Year must be a four-digit year.';
  end if;

  if p_exam_month is null or p_exam_month not between 1 and 12 then
    raise exception 'Month must be 1–12.';
  end if;
end;
$$;

-- Point this question at a paper for the sitting. Does not enqueue.
create or replace function public.admin_retarget_appearance(
  p_question_id uuid,
  p_old_paper_id uuid,
  p_subject_id uuid,
  p_university_id uuid,
  p_college_id uuid,
  p_exam_year int,
  p_exam_month int,
  p_paper_name text,
  p_exam_type text
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_paper_name text := nullif(btrim(coalesce(p_paper_name, '')), '');
  v_external_id text;
  v_new_id uuid;
begin
  perform public.admin_validate_sitting(
    p_university_id,
    p_college_id,
    p_subject_id,
    p_exam_year,
    p_exam_month,
    p_exam_type
  );

  v_external_id := public.admin_paper_external_id(
    p_university_id,
    p_college_id,
    p_subject_id,
    p_exam_type,
    p_exam_year,
    p_exam_month,
    v_paper_name
  );

  insert into public.exam_papers (
    external_id, university_id, college_id, subject_id,
    exam_year, exam_month, paper_name, exam_type
  ) values (
    v_external_id, p_university_id, p_college_id, p_subject_id,
    p_exam_year, p_exam_month::smallint, v_paper_name, p_exam_type
  )
  on conflict (external_id) do update set
    university_id = excluded.university_id,
    college_id = excluded.college_id,
    subject_id = excluded.subject_id,
    exam_year = excluded.exam_year,
    exam_month = excluded.exam_month,
    paper_name = excluded.paper_name,
    exam_type = excluded.exam_type
  returning id into v_new_id;

  insert into public.question_appearances (question_id, exam_paper_id)
  values (p_question_id, v_new_id)
  on conflict do nothing;

  if p_old_paper_id is not null and p_old_paper_id is distinct from v_new_id then
    delete from public.question_appearances
    where question_id = p_question_id
      and exam_paper_id = p_old_paper_id;

    delete from public.exam_papers ep
    where ep.id = p_old_paper_id
      and ep.external_id like 'CSV-EP-%'
      and not exists (
        select 1
        from public.question_appearances qa
        where qa.exam_paper_id = ep.id
      );
  end if;

  return v_new_id;
end;
$$;

create or replace function public.admin_question_subject_name(p_question_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (
      select s.name
      from public.questions q
      join public.topics t on t.id = q.topic_id
      join public.subjects s on s.id = t.subject_id
      where q.id = p_question_id
    ),
    (
      select s.name
      from public.question_appearances qa
      join public.exam_papers ep on ep.id = qa.exam_paper_id
      join public.subjects s on s.id = ep.subject_id
      where qa.question_id = p_question_id
      order by ep.exam_year desc
      limit 1
    )
  );
$$;

create or replace function public.admin_ensure_topic_lesson(
  p_subject_id uuid,
  p_chapter text,
  p_topic text,
  p_required_plan public.plan_tier,
  p_is_active boolean
) returns table (topic_id uuid, lesson_id uuid)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_chapter text := nullif(btrim(coalesce(p_chapter, '')), '');
  v_topic text := nullif(btrim(coalesce(p_topic, '')), '');
  v_topic_id uuid;
  v_lesson_id uuid;
begin
  if v_topic is not null and v_chapter is null then
    raise exception 'Add a chapter before a topic.';
  end if;

  if v_chapter is null then
    topic_id := null;
    lesson_id := null;
    return next;
    return;
  end if;

  select t.id into v_topic_id
  from public.topics t
  where t.subject_id = p_subject_id
    and lower(t.name) = lower(v_chapter)
  order by t.id
  limit 1;

  if v_topic_id is null then
    insert into public.topics (subject_id, name, display_order)
    values (
      p_subject_id,
      v_chapter,
      (
        select coalesce(max(display_order), 0) + 1
        from public.topics
        where subject_id = p_subject_id
      )
    )
    returning id into v_topic_id;
  end if;

  if v_topic is not null then
    select l.id into v_lesson_id
    from public.lessons l
    where l.topic_id = v_topic_id
      and lower(l.name) = lower(v_topic)
    order by l.id
    limit 1;

    if v_lesson_id is null then
      insert into public.lessons (
        topic_id, external_id, name, display_order, required_plan, is_active
      ) values (
        v_topic_id,
        'CSV-L-' || upper(substr(md5(
          p_subject_id::text || '|' || v_topic_id::text || '|' || lower(v_topic)
        ), 1, 24)),
        v_topic,
        (
          select coalesce(max(display_order), 0) + 1
          from public.lessons
          where topic_id = v_topic_id
        ),
        p_required_plan,
        p_is_active
      )
      returning id into v_lesson_id;
    end if;
  end if;

  topic_id := v_topic_id;
  lesson_id := v_lesson_id;
  return next;
end;
$$;

revoke all on function public.admin_question_external_id(text, text, text) from public, anon, authenticated;
revoke all on function public.admin_paper_external_id(uuid, uuid, uuid, text, int, int, text) from public, anon, authenticated;
revoke all on function public.admin_exam_type_label(text) from public, anon, authenticated;
revoke all on function public.admin_month_name(int) from public, anon, authenticated;
revoke all on function public.admin_sheet_row(uuid, uuid) from public, anon, authenticated;
revoke all on function public.admin_sheet_match(text, text, text, uuid) from public, anon, authenticated;
revoke all on function public.admin_enqueue_sheet(uuid, uuid, text, jsonb) from public, anon, authenticated;
revoke all on function public.admin_validate_sitting(uuid, uuid, uuid, int, int, text) from public, anon, authenticated;
revoke all on function public.admin_retarget_appearance(uuid, uuid, uuid, uuid, uuid, int, int, text, text) from public, anon, authenticated;
revoke all on function public.admin_question_subject_name(uuid) from public, anon, authenticated;
revoke all on function public.admin_ensure_topic_lesson(uuid, text, text, public.plan_tier, boolean) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Question search / read / write
-- ---------------------------------------------------------------------------

create or replace function public.admin_search_questions(p_query text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_query text := nullif(btrim(coalesce(p_query, '')), '');
begin
  perform public.assert_admin();

  if v_query is not null then
    v_query := replace(replace(v_query, '%', ''), '_', '');
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', q.id,
      'question_text', q.question_text,
      'kind', q.kind,
      'marks', q.marks,
      'required_plan', q.required_plan,
      'is_active', q.is_active,
      'subject_name', public.admin_question_subject_name(q.id),
      'appearance_count', (
        select count(*)::int
        from public.question_appearances qa
        where qa.question_id = q.id
      )
    ) order by q.created_at desc)
    from (
      select q.id, q.created_at
      from public.questions q
      where v_query is null
        or q.question_text ilike '%' || v_query || '%'
        or public.admin_question_subject_name(q.id) ilike '%' || v_query || '%'
      order by q.created_at desc
      limit 40
    ) picked
    join public.questions q on q.id = picked.id
  ), '[]'::jsonb);
end;
$$;

create or replace function public.admin_get_question(p_question_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_row jsonb;
begin
  perform public.assert_admin();

  select jsonb_build_object(
    'id', q.id,
    'external_id', q.external_id,
    'question_text', q.question_text,
    'kind', q.kind,
    'marks', q.marks,
    'difficulty', q.difficulty,
    'required_plan', q.required_plan,
    'is_active', q.is_active,
    'option_a', q.option_a,
    'option_b', q.option_b,
    'option_c', q.option_c,
    'option_d', q.option_d,
    'correct_option', q.correct_option,
    'explanation_text', q.explanation_text,
    'explanation_deep', q.explanation_deep,
    'sample_answer', sa.body,
    'chapter_name', top.name,
    'topic_name', les.name,
    'subject_id', coalesce(top.subject_id, (
      select ep.subject_id
      from public.question_appearances qa
      join public.exam_papers ep on ep.id = qa.exam_paper_id
      where qa.question_id = q.id
      order by ep.exam_year desc
      limit 1
    )),
    'subject_name', public.admin_question_subject_name(q.id),
    'appearances', coalesce((
      select jsonb_agg(jsonb_build_object(
        'exam_paper_id', ep.id,
        'university_id', ep.university_id,
        'university_name', u.name,
        'college_id', ep.college_id,
        'college_name', c.name,
        'exam_year', ep.exam_year,
        'exam_month', ep.exam_month,
        'paper_name', ep.paper_name,
        'exam_type', ep.exam_type
      ) order by ep.exam_year desc, ep.exam_month desc nulls last)
      from public.question_appearances qa
      join public.exam_papers ep on ep.id = qa.exam_paper_id
      join public.universities u on u.id = ep.university_id
      left join public.colleges c on c.id = ep.college_id
      where qa.question_id = q.id
    ), '[]'::jsonb)
  )
  into v_row
  from public.questions q
  left join public.question_sample_answers sa on sa.question_id = q.id
  left join public.topics top on top.id = q.topic_id
  left join public.lessons les on les.id = q.lesson_id
  where q.id = p_question_id;

  if v_row is null then
    raise exception 'Question not found.';
  end if;

  return v_row;
end;
$$;

create or replace function public.admin_save_question(p_body jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid := nullif(p_body->>'id', '')::uuid;
  v_is_insert boolean := false;
  v_subject_id uuid := nullif(p_body->>'subject_id', '')::uuid;
  v_subject_name text;
  v_stem text := nullif(btrim(coalesce(p_body->>'question_text', '')), '');
  v_kind text := lower(btrim(coalesce(p_body->>'kind', '')));
  v_marks numeric;
  v_difficulty text := lower(btrim(coalesce(nullif(p_body->>'difficulty', ''), 'should')));
  v_plan text := lower(btrim(coalesce(nullif(p_body->>'required_plan', ''), 'free')));
  v_active boolean := coalesce((p_body->>'is_active')::boolean, true);
  v_option_a text;
  v_option_b text;
  v_option_c text;
  v_option_d text;
  v_correct text;
  v_exp_1 text := nullif(btrim(coalesce(p_body->>'explanation_text', '')), '');
  v_exp_2 text := nullif(btrim(coalesce(p_body->>'explanation_deep', '')), '');
  v_answer text := nullif(btrim(coalesce(p_body->>'sample_answer', '')), '');
  v_chapter text := p_body->>'chapter_name';
  v_topic text := p_body->>'topic_name';
  v_topic_id uuid;
  v_lesson_id uuid;
  v_external_id text;
  v_old_subject text;
  v_old_kind text;
  v_old_stem text;
  v_paper_id uuid;
  v_paper_ids uuid[] := '{}';
  v_match jsonb;
  v_sitting jsonb;
  r record;
begin
  perform public.assert_admin();
  v_is_insert := v_id is null;

  if v_subject_id is null or not exists (
    select 1 from public.subjects where id = v_subject_id
  ) then
    raise exception 'Choose a subject that already exists.';
  end if;

  select name into v_subject_name from public.subjects where id = v_subject_id;

  if v_stem is null then
    raise exception 'Question text is required.';
  end if;

  if v_kind not in ('mcq', 'pyq_theory') then
    raise exception 'Question type must be pyq_theory or mcq.';
  end if;

  if v_plan not in ('free', 'pro', 'elite') then
    raise exception 'Pick a plan of free, pro, or elite.';
  end if;

  if v_difficulty not in ('must', 'should', 'could') then
    raise exception 'Difficulty must be must, should, or could.';
  end if;

  begin
    if nullif(btrim(coalesce(p_body->>'marks', '')), '') is null then
      v_marks := null;
    else
      v_marks := (p_body->>'marks')::numeric;
    end if;
  exception
    when others then
      raise exception 'Marks must be a number.';
  end;

  if v_kind = 'mcq' then
    v_option_a := nullif(btrim(coalesce(p_body->>'option_a', '')), '');
    v_option_b := nullif(btrim(coalesce(p_body->>'option_b', '')), '');
    v_option_c := nullif(btrim(coalesce(p_body->>'option_c', '')), '');
    v_option_d := nullif(btrim(coalesce(p_body->>'option_d', '')), '');
    v_correct := nullif(upper(btrim(coalesce(p_body->>'correct_option', ''))), '');
    if v_option_a is null or v_option_b is null or v_option_c is null
      or v_option_d is null or v_correct is null
      or v_correct not in ('A', 'B', 'C', 'D') then
      raise exception 'MCQ questions need four options and a correct option (A–D).';
    end if;
  else
    v_option_a := null;
    v_option_b := null;
    v_option_c := null;
    v_option_d := null;
    v_correct := null;
  end if;

  select topic_id, lesson_id
  into v_topic_id, v_lesson_id
  from public.admin_ensure_topic_lesson(
    v_subject_id,
    v_chapter,
    v_topic,
    v_plan::public.plan_tier,
    v_active
  );

  v_external_id := public.admin_question_external_id(v_subject_name, v_kind, v_stem);

  if v_is_insert then
    if exists (
      select 1 from public.questions where external_id = v_external_id
    ) then
      raise exception 'A question with this subject, type, and stem already exists.';
    end if;

    v_sitting := p_body->'sitting';
    if v_sitting is null or v_sitting = 'null'::jsonb then
      raise exception 'A new question needs a paper (university, year, month, and exam type).';
    end if;

    insert into public.questions (
      external_id, topic_id, lesson_id, kind, question_text,
      option_a, option_b, option_c, option_d, correct_option,
      explanation_text, explanation_deep, difficulty, marks,
      required_plan, is_active, content_sync_source
    ) values (
      v_external_id, v_topic_id, v_lesson_id, v_kind::public.question_kind, v_stem,
      v_option_a, v_option_b, v_option_c, v_option_d, v_correct,
      v_exp_1, v_exp_2, v_difficulty::public.question_difficulty, v_marks,
      v_plan::public.plan_tier, v_active, 'questions_csv_v2'
    )
    returning id into v_id;
  else
    select q.kind::text, q.question_text
    into v_old_kind, v_old_stem
    from public.questions q
    where q.id = v_id;

    if v_old_stem is null then
      raise exception 'Question not found.';
    end if;

    v_old_subject := public.admin_question_subject_name(v_id);

    if exists (
      select 1
      from public.questions
      where external_id = v_external_id
        and id <> v_id
    ) then
      raise exception 'A question with this subject, type, and stem already exists.';
    end if;

    update public.questions
    set
      external_id = v_external_id,
      topic_id = v_topic_id,
      lesson_id = v_lesson_id,
      kind = v_kind::public.question_kind,
      question_text = v_stem,
      option_a = v_option_a,
      option_b = v_option_b,
      option_c = v_option_c,
      option_d = v_option_d,
      correct_option = v_correct,
      explanation_text = v_exp_1,
      explanation_deep = v_exp_2,
      difficulty = v_difficulty::public.question_difficulty,
      marks = v_marks,
      required_plan = v_plan::public.plan_tier,
      is_active = v_active,
      content_sync_source = 'questions_csv_v2'
    where id = v_id;
  end if;

  if v_answer is null then
    delete from public.question_sample_answers where question_id = v_id;
  else
    insert into public.question_sample_answers (question_id, body, updated_at)
    values (v_id, v_answer, now())
    on conflict (question_id) do update
      set body = excluded.body, updated_at = now();
  end if;

  if v_is_insert then
    v_paper_id := public.admin_retarget_appearance(
      v_id,
      null,
      v_subject_id,
      nullif(v_sitting->>'university_id', '')::uuid,
      nullif(v_sitting->>'college_id', '')::uuid,
      nullif(v_sitting->>'exam_year', '')::int,
      nullif(v_sitting->>'exam_month', '')::int,
      v_sitting->>'paper_name',
      lower(btrim(coalesce(v_sitting->>'exam_type', '')))
    );
    -- No previous sheet row: Apps Script appends.
    perform public.admin_enqueue_sheet(v_id, v_paper_id, 'upsert', null);
  else
    for r in
      select
        ep.id,
        ep.university_id,
        ep.college_id,
        ep.subject_id,
        ep.exam_year,
        ep.exam_month,
        ep.paper_name,
        ep.exam_type
      from public.question_appearances qa
      join public.exam_papers ep on ep.id = qa.exam_paper_id
      where qa.question_id = v_id
    loop
      -- Papers imported before month was required cannot be re-hashed until
      -- an admin sets a month. Leave them in place when the subject is unchanged.
      if r.exam_month is null and r.subject_id is distinct from v_subject_id then
        raise exception 'Set a month on every paper before changing the subject.';
      end if;

      if r.exam_month is null then
        v_paper_id := r.id;
      else
        v_paper_id := public.admin_retarget_appearance(
          v_id,
          r.id,
          v_subject_id,
          r.university_id,
          r.college_id,
          r.exam_year,
          r.exam_month::int,
          r.paper_name,
          r.exam_type
        );
      end if;
      if array_position(v_paper_ids, v_paper_id) is null then
        v_paper_ids := array_append(v_paper_ids, v_paper_id);
      end if;
    end loop;

    foreach v_paper_id in array v_paper_ids loop
      v_match := public.admin_sheet_match(
        v_old_subject,
        v_old_kind,
        v_old_stem,
        v_paper_id
      );
      perform public.admin_enqueue_sheet(v_id, v_paper_id, 'upsert', v_match);
    end loop;
  end if;

  perform public.admin_log_action(
    'save_question',
    v_id,
    jsonb_build_object('required_plan', v_plan, 'kind', v_kind, 'is_active', v_active)
  );

  return jsonb_build_object('id', v_id);
end;
$$;

create or replace function public.admin_save_appearance(p_body jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_question_id uuid := nullif(p_body->>'question_id', '')::uuid;
  v_old_paper_id uuid := nullif(p_body->>'exam_paper_id', '')::uuid;
  v_subject_id uuid;
  v_subject text;
  v_kind text;
  v_stem text;
  v_match jsonb;
  v_new_paper_id uuid;
begin
  perform public.assert_admin();

  if v_question_id is null or not exists (
    select 1 from public.questions where id = v_question_id
  ) then
    raise exception 'Question not found.';
  end if;

  select coalesce(t.subject_id, ep.subject_id)
  into v_subject_id
  from public.questions q
  left join public.topics t on t.id = q.topic_id
  left join lateral (
    select e.subject_id
    from public.question_appearances qa
    join public.exam_papers e on e.id = qa.exam_paper_id
    where qa.question_id = q.id
    order by e.exam_year desc
    limit 1
  ) ep on true
  where q.id = v_question_id;

  if v_old_paper_id is not null then
    if not exists (
      select 1
      from public.question_appearances
      where question_id = v_question_id
        and exam_paper_id = v_old_paper_id
    ) then
      raise exception 'That paper is not on this question.';
    end if;

    select q.kind::text, q.question_text
    into v_kind, v_stem
    from public.questions q
    where q.id = v_question_id;

    v_subject := public.admin_question_subject_name(v_question_id);
    v_match := public.admin_sheet_match(v_subject, v_kind, v_stem, v_old_paper_id);
  end if;

  v_new_paper_id := public.admin_retarget_appearance(
    v_question_id,
    v_old_paper_id,
    v_subject_id,
    nullif(p_body->>'university_id', '')::uuid,
    nullif(p_body->>'college_id', '')::uuid,
    nullif(p_body->>'exam_year', '')::int,
    nullif(p_body->>'exam_month', '')::int,
    p_body->>'paper_name',
    lower(btrim(coalesce(p_body->>'exam_type', '')))
  );

  perform public.admin_enqueue_sheet(
    v_question_id,
    v_new_paper_id,
    'upsert',
    v_match
  );

  perform public.admin_log_action(
    'save_appearance',
    v_question_id,
    jsonb_build_object('exam_paper_id', v_new_paper_id)
  );

  return jsonb_build_object(
    'question_id', v_question_id,
    'exam_paper_id', v_new_paper_id
  );
end;
$$;

create or replace function public.admin_delete_appearance(
  p_question_id uuid,
  p_exam_paper_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count int;
  v_kind text;
  v_stem text;
  v_subject text;
  v_match jsonb;
begin
  perform public.assert_admin();

  if not exists (
    select 1
    from public.question_appearances
    where question_id = p_question_id
      and exam_paper_id = p_exam_paper_id
  ) then
    raise exception 'That paper is not on this question.';
  end if;

  select count(*)::int into v_count
  from public.question_appearances
  where question_id = p_question_id;

  if v_count < 2 then
    raise exception 'Keep at least one paper on this question.';
  end if;

  select q.kind::text, q.question_text
  into v_kind, v_stem
  from public.questions q
  where q.id = p_question_id;

  v_subject := public.admin_question_subject_name(p_question_id);
  v_match := public.admin_sheet_match(v_subject, v_kind, v_stem, p_exam_paper_id);

  delete from public.question_appearances
  where question_id = p_question_id
    and exam_paper_id = p_exam_paper_id;

  delete from public.exam_papers ep
  where ep.id = p_exam_paper_id
    and ep.external_id like 'CSV-EP-%'
    and not exists (
      select 1 from public.question_appearances qa
      where qa.exam_paper_id = ep.id
    );

  perform public.admin_enqueue_sheet(p_question_id, p_exam_paper_id, 'delete', v_match);
  perform public.admin_log_action(
    'delete_appearance',
    p_question_id,
    jsonb_build_object('exam_paper_id', p_exam_paper_id)
  );

  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.admin_search_questions(text) from public, anon;
revoke all on function public.admin_get_question(uuid) from public, anon;
revoke all on function public.admin_save_question(jsonb) from public, anon;
revoke all on function public.admin_save_appearance(jsonb) from public, anon;
revoke all on function public.admin_delete_appearance(uuid, uuid) from public, anon;

grant execute on function public.admin_search_questions(text) to authenticated;
grant execute on function public.admin_get_question(uuid) to authenticated;
grant execute on function public.admin_save_question(jsonb) to authenticated;
grant execute on function public.admin_save_appearance(jsonb) to authenticated;
grant execute on function public.admin_delete_appearance(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Apps Script pull (service_role only)
-- ---------------------------------------------------------------------------

create or replace function public.export_sheet_outbox()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', s.id,
      'op', s.op,
      'match', s.match_key,
      'row', s.row_payload
    ) order by s.created_at)
    from (
      select id, op, match_key, row_payload, created_at
      from public.sheet_outbox
      where applied_at is null
      order by created_at
      limit 200
    ) s
  ), '[]'::jsonb);
$$;

create or replace function public.ack_sheet_outbox(p_ids uuid[])
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count int;
begin
  update public.sheet_outbox
  set applied_at = now()
  where id = any(coalesce(p_ids, '{}'::uuid[]))
    and applied_at is null;

  get diagnostics v_count = row_count;

  return jsonb_build_object('ok', true, 'acked', v_count);
end;
$$;

comment on function public.export_sheet_outbox() is
  'Pending question edits for the Questions tab. service_role only.';

comment on function public.ack_sheet_outbox(uuid[]) is
  'Marks pulled outbox rows applied. service_role only.';

revoke all on function public.export_sheet_outbox() from public, anon, authenticated;
revoke all on function public.ack_sheet_outbox(uuid[]) from public, anon, authenticated;
grant execute on function public.export_sheet_outbox() to service_role;
grant execute on function public.ack_sheet_outbox(uuid[]) to service_role;
