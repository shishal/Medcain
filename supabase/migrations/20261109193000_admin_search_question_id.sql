-- Question search also matches the question id: the six-digit public code,
-- the legacy external id, and the UUID (including one pasted from an editor link).

create or replace function public.admin_search_questions(p_query text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_query text := nullif(btrim(coalesce(p_query, '')), '');
  v_question_id uuid;
  v_uuid_text text;
begin
  perform public.assert_admin();

  if v_query is not null then
    v_query := replace(replace(v_query, '%', ''), '_', '');
    v_uuid_text := substring(
      lower(v_query)
      from '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
    );
    if v_uuid_text is not null then
      v_question_id := v_uuid_text::uuid;
    end if;
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', q.id,
      'public_code', q.public_code,
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
        or (
          v_query ~ '^[0-9]{1,6}$'
          and q.public_code = lpad(v_query, 6, '0')
        )
        or (v_question_id is not null and q.id = v_question_id)
        or lower(q.external_id) = lower(v_query)
      order by q.created_at desc
      limit 40
    ) picked
    join public.questions q on q.id = picked.id
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.admin_search_questions(text) from public, anon;
grant execute on function public.admin_search_questions(text) to authenticated;

create or replace function public.admin_search_questions_filtered(p_filters jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_filters jsonb := coalesce(p_filters, '{}'::jsonb);
  v_query text;
  v_state text;
  v_university_id uuid;
  v_college_id uuid;
  v_year int;
  v_month int;
  v_exam_type text;
  v_subject_id uuid;
  v_kind text;
  v_plan text;
  v_active boolean;
  v_limit int;
  v_offset int;
  v_result jsonb;
  v_question_id uuid;
  v_uuid_text text;
begin
  perform public.assert_admin();

  if jsonb_typeof(v_filters) <> 'object' then
    raise exception 'Filters must be an object.';
  end if;

  v_query := nullif(btrim(coalesce(v_filters->>'query', '')), '');
  v_question_id := null;
  if v_query is not null then
    v_query := replace(replace(replace(v_query, '\', ''), '%', ''), '_', '');
    v_query := nullif(left(v_query, 200), '');
  end if;
  if v_query is not null then
    v_uuid_text := substring(
      lower(v_query)
      from '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
    );
    if v_uuid_text is not null then
      v_question_id := v_uuid_text::uuid;
    end if;
  end if;

  v_state := nullif(btrim(coalesce(v_filters->>'state', '')), '');

  begin
    v_university_id := nullif(btrim(coalesce(v_filters->>'university_id', '')), '')::uuid;
  exception
    when invalid_text_representation then
      raise exception 'Choose a university from the list.';
  end;

  begin
    v_college_id := nullif(btrim(coalesce(v_filters->>'college_id', '')), '')::uuid;
  exception
    when invalid_text_representation then
      raise exception 'Choose a college from the list.';
  end;

  begin
    v_subject_id := nullif(btrim(coalesce(v_filters->>'subject_id', '')), '')::uuid;
  exception
    when invalid_text_representation then
      raise exception 'Choose a subject from the list.';
  end;

  begin
    if nullif(btrim(coalesce(v_filters->>'exam_year', '')), '') is null then
      v_year := null;
    else
      v_year := (v_filters->>'exam_year')::int;
    end if;
  exception
    when invalid_text_representation or numeric_value_out_of_range then
      raise exception 'Year must be a number from 1990 to 2100.';
  end;
  if v_year is not null and (v_year < 1990 or v_year > 2100) then
    raise exception 'Year must be a number from 1990 to 2100.';
  end if;

  begin
    if nullif(btrim(coalesce(v_filters->>'exam_month', '')), '') is null then
      v_month := null;
    else
      v_month := (v_filters->>'exam_month')::int;
    end if;
  exception
    when invalid_text_representation or numeric_value_out_of_range then
      raise exception 'Month must be a number from 1 to 12.';
  end;
  if v_month is not null and (v_month < 1 or v_month > 12) then
    raise exception 'Month must be a number from 1 to 12.';
  end if;

  v_exam_type := nullif(lower(btrim(coalesce(v_filters->>'exam_type', ''))), '');
  if v_exam_type is not null and v_exam_type not in ('prof', 'supply', 'pre_prof', 'internal') then
    raise exception 'Exam type must be prof, supply, pre_prof, or internal.';
  end if;

  v_kind := nullif(lower(btrim(coalesce(v_filters->>'kind', ''))), '');
  if v_kind is not null and v_kind not in ('mcq', 'pyq_theory') then
    raise exception 'Question type must be pyq_theory or mcq.';
  end if;

  v_plan := nullif(lower(btrim(coalesce(v_filters->>'required_plan', ''))), '');
  if v_plan is not null and v_plan not in ('free', 'pro', 'elite') then
    raise exception 'Pick a plan of free, pro, or elite.';
  end if;

  if v_filters ? 'is_active' and jsonb_typeof(v_filters->'is_active') <> 'null' then
    if jsonb_typeof(v_filters->'is_active') <> 'boolean' then
      raise exception 'Visible filter must be true or false.';
    end if;
    v_active := (v_filters->>'is_active')::boolean;
  end if;

  begin
    v_limit := coalesce(nullif(btrim(coalesce(v_filters->>'limit', '')), '')::int, 50);
    v_offset := coalesce(nullif(btrim(coalesce(v_filters->>'offset', '')), '')::int, 0);
  exception
    when invalid_text_representation or numeric_value_out_of_range then
      raise exception 'Page size and offset must be numbers.';
  end;
  if v_limit < 1 then
    v_limit := 1;
  elsif v_limit > 50 then
    v_limit := 50;
  end if;
  if v_offset < 0 then
    v_offset := 0;
  end if;

  with matched as (
    select q.id, q.created_at
    from public.questions q
    where (v_kind is null or q.kind::text = v_kind)
      and (v_plan is null or q.required_plan::text = v_plan)
      and (v_active is null or q.is_active = v_active)
      and (
        v_query is null
        or q.question_text ilike '%' || v_query || '%'
        or public.admin_question_subject_name(q.id) ilike '%' || v_query || '%'
        or (
          v_query ~ '^[0-9]{1,6}$'
          and q.public_code = lpad(v_query, 6, '0')
        )
        or (v_question_id is not null and q.id = v_question_id)
        or lower(q.external_id) = lower(v_query)
      )
      and (
        v_subject_id is null
        or exists (
          select 1
          from public.topics t
          where t.id = q.topic_id
            and t.subject_id = v_subject_id
        )
        or exists (
          select 1
          from public.question_appearances qa
          join public.exam_papers ep on ep.id = qa.exam_paper_id
          where qa.question_id = q.id
            and ep.subject_id = v_subject_id
        )
      )
      and (
        (
          v_state is null
          and v_university_id is null
          and v_college_id is null
          and v_year is null
          and v_month is null
          and v_exam_type is null
        )
        or exists (
          select 1
          from public.question_appearances qa
          join public.exam_papers ep on ep.id = qa.exam_paper_id
          join public.universities u on u.id = ep.university_id
          where qa.question_id = q.id
            and (v_state is null or lower(u.state) = lower(v_state))
            and (v_university_id is null or ep.university_id = v_university_id)
            and (v_college_id is null or ep.college_id = v_college_id)
            and (v_year is null or ep.exam_year = v_year)
            and (v_month is null or ep.exam_month = v_month)
            and (v_exam_type is null or ep.exam_type = v_exam_type)
        )
      )
  )
  select jsonb_build_object(
    'total', (select count(*)::int from matched),
    'limit', v_limit,
    'offset', v_offset,
    'questions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', q.id,
        'public_code', q.public_code,
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
      ) order by picked.created_at desc)
      from (
        select m.id, m.created_at
        from matched m
        order by m.created_at desc
        limit v_limit
        offset v_offset
      ) picked
      join public.questions q on q.id = picked.id
    ), '[]'::jsonb)
  )
  into v_result;

  return v_result;
end;
$$;

comment on function public.admin_search_questions_filtered(jsonb) is
  'Admin question list. Text matches the stem, subject, six-digit id, legacy id, or question UUID. Filters combine on one sitting.';

revoke all on function public.admin_search_questions_filtered(jsonb) from public, anon;
grant execute on function public.admin_search_questions_filtered(jsonb) to authenticated;
