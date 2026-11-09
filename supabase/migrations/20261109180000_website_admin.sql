-- Website admin. New RPCs sit beside the Flutter ones.
-- Question saves still queue sheet_outbox. A textbook or resource key that
-- the client omits is left unchanged, so the app admin can keep saving.

-- ---------------------------------------------------------------------------
-- Textbook page ref and one resource link on a question save
-- ---------------------------------------------------------------------------

create or replace function public.admin_apply_question_extras(
  p_question_id uuid,
  p_body jsonb
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tb jsonb;
  v_res jsonb;
  v_title text;
  v_authors text;
  v_edition text;
  v_page_text text;
  v_section text;
  v_url text;
  v_source text;
  v_free boolean;
  v_textbook_id uuid;
  v_key text;
begin
  perform public.assert_admin();

  if p_body ? 'textbook' then
    delete from public.question_textbook_refs
    where question_id = p_question_id;

    v_tb := p_body->'textbook';
    if jsonb_typeof(v_tb) = 'object' then
      v_title := nullif(btrim(coalesce(v_tb->>'title', '')), '');
      v_authors := nullif(btrim(coalesce(v_tb->>'authors', '')), '');
      v_edition := nullif(btrim(coalesce(v_tb->>'edition', '')), '');
      v_page_text := nullif(btrim(coalesce(v_tb->>'page', '')), '');
      v_section := nullif(btrim(coalesce(v_tb->>'section_heading', '')), '');

      if v_title is not null or v_page_text is not null
        or v_authors is not null or v_edition is not null or v_section is not null
      then
        if v_title is null or v_page_text is null then
          raise exception 'Textbook title and page must be filled together.';
        end if;
        if v_page_text !~ '^[0-9]+$' or v_page_text::int <= 0 then
          raise exception 'Page must be a positive integer.';
        end if;

        v_key := 'CSV-TB-' || upper(substr(md5(
          lower(v_title) || '|' || lower(coalesce(v_edition, ''))
        ), 1, 24));

        insert into public.textbooks (sheet_key, title, authors, edition)
        values (v_key, v_title, v_authors, v_edition)
        on conflict (sheet_key) do update
          set title = excluded.title,
              authors = excluded.authors,
              edition = excluded.edition
        returning id into v_textbook_id;

        insert into public.question_textbook_refs (
          question_id, textbook_id, page, section_heading
        ) values (
          p_question_id, v_textbook_id, v_page_text::int, v_section
        )
        on conflict (question_id, textbook_id, page) do update
          set section_heading = excluded.section_heading;
      end if;
    end if;
  end if;

  if p_body ? 'resource' then
    delete from public.question_resources
    where question_id = p_question_id;

    v_res := p_body->'resource';
    if jsonb_typeof(v_res) = 'object' then
      v_title := nullif(btrim(coalesce(v_res->>'title', '')), '');
      v_url := nullif(btrim(coalesce(v_res->>'url', '')), '');
      v_source := nullif(btrim(coalesce(v_res->>'source_label', '')), '');

      if v_title is not null or v_url is not null or v_source is not null then
        if v_title is null or v_url is null then
          raise exception 'Resource title and link must be filled together.';
        end if;
        if v_url !~ '^https://' then
          raise exception 'Resource link must start with https://';
        end if;
        if v_res ? 'is_free' and jsonb_typeof(v_res->'is_free') <> 'boolean' then
          raise exception 'Resource free flag must be true or false.';
        end if;
        v_free := case
          when v_res ? 'is_free' then (v_res->>'is_free')::boolean
          else true
        end;

        insert into public.question_resources (
          question_id, title, url, source_label, display_order, is_free
        ) values (
          p_question_id, v_title, v_url, v_source, 1, v_free
        );
      end if;
    end if;
  end if;
end;
$$;

comment on function public.admin_apply_question_extras(uuid, jsonb) is
  'Writes the optional textbook and resource keys on an admin question save. Omitted keys are left as they are. One textbook and one link, matching the question sheet.';

revoke all on function public.admin_apply_question_extras(uuid, jsonb) from public, anon, authenticated;

-- REPLACED_FUNCTIONS

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
  v_code text;
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

  if v_is_insert then
    v_sitting := p_body->'sitting';
    if v_sitting is null or v_sitting = 'null'::jsonb then
      raise exception 'A new question needs a paper (university, year, month, and exam type).';
    end if;

    v_external_id := public.allocate_question_public_code();

    insert into public.questions (
      external_id, public_code, topic_id, lesson_id, kind, question_text,
      option_a, option_b, option_c, option_d, correct_option,
      explanation_text, explanation_deep, difficulty, marks,
      required_plan, is_active, content_sync_source
    ) values (
      v_external_id, v_external_id, v_topic_id, v_lesson_id, v_kind::public.question_kind, v_stem,
      v_option_a, v_option_b, v_option_c, v_option_d, v_correct,
      v_exp_1, v_exp_2, v_difficulty::public.question_difficulty, v_marks,
      v_plan::public.plan_tier, v_active, 'questions_csv_v2'
    )
    returning id into v_id;
  else
    select q.kind::text, q.question_text, q.external_id, q.public_code
    into v_old_kind, v_old_stem, v_external_id, v_code
    from public.questions q
    where q.id = v_id;

    if v_old_stem is null then
      raise exception 'Question not found.';
    end if;

    v_old_subject := public.admin_question_subject_name(v_id);

    if v_code is null then
      if v_external_id ~ '^[0-9]{6}$' then
        v_code := v_external_id;
      else
        v_code := public.allocate_question_public_code();
      end if;
    end if;
    v_external_id := v_code;

    update public.questions
    set
      external_id = v_external_id,
      public_code = v_code,
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

  perform public.admin_apply_question_extras(v_id, p_body);

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
    'question_id', coalesce(q.public_code, ''),
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
    'state', coalesce(u.state, ''),
    'textbook_title', coalesce((
      select tb.title
      from public.question_textbook_refs r
      join public.textbooks tb on tb.id = r.textbook_id
      where r.question_id = q.id
      order by r.page
      limit 1
    ), ''),
    'textbook_authors', coalesce((
      select tb.authors
      from public.question_textbook_refs r
      join public.textbooks tb on tb.id = r.textbook_id
      where r.question_id = q.id
      order by r.page
      limit 1
    ), ''),
    'textbook_edition', coalesce((
      select tb.edition
      from public.question_textbook_refs r
      join public.textbooks tb on tb.id = r.textbook_id
      where r.question_id = q.id
      order by r.page
      limit 1
    ), ''),
    'page', coalesce((
      select r.page::text
      from public.question_textbook_refs r
      where r.question_id = q.id
      order by r.page
      limit 1
    ), ''),
    'section_heading', coalesce((
      select r.section_heading
      from public.question_textbook_refs r
      where r.question_id = q.id
      order by r.page
      limit 1
    ), ''),
    'resource_title', coalesce((
      select qr.title
      from public.question_resources qr
      where qr.question_id = q.id
      order by qr.display_order, qr.url
      limit 1
    ), ''),
    'resource_url', coalesce((
      select qr.url
      from public.question_resources qr
      where qr.question_id = q.id
      order by qr.display_order, qr.url
      limit 1
    ), ''),
    'resource_source_label', coalesce((
      select qr.source_label
      from public.question_resources qr
      where qr.question_id = q.id
      order by qr.display_order, qr.url
      limit 1
    ), ''),
    'resource_is_free', coalesce((
      select case when qr.is_free then 'TRUE' else 'FALSE' end
      from public.question_resources qr
      where qr.question_id = q.id
      order by qr.display_order, qr.url
      limit 1
    ), '')
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
    'public_code', q.public_code,
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
    'textbook', (
      select jsonb_build_object(
        'title', tb.title,
        'authors', tb.authors,
        'edition', tb.edition,
        'page', r.page,
        'section_heading', r.section_heading
      )
      from public.question_textbook_refs r
      join public.textbooks tb on tb.id = r.textbook_id
      where r.question_id = q.id
      order by r.page
      limit 1
    ),
    'resource', (
      select jsonb_build_object(
        'title', qr.title,
        'url', qr.url,
        'source_label', qr.source_label,
        'is_free', qr.is_free
      )
      from public.question_resources qr
      where qr.question_id = q.id
      order by qr.display_order, qr.url
      limit 1
    ),
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


-- ---------------------------------------------------------------------------
-- Filtered question search. The Flutter text search is unchanged.
-- ---------------------------------------------------------------------------

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
begin
  perform public.assert_admin();

  if jsonb_typeof(v_filters) <> 'object' then
    raise exception 'Filters must be an object.';
  end if;

  v_query := nullif(btrim(coalesce(v_filters->>'query', '')), '');
  if v_query is not null then
    v_query := replace(replace(replace(v_query, '\', ''), '%', ''), '_', '');
    v_query := nullif(left(v_query, 200), '');
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
  'Admin question list. Filters combine on one sitting. Returns one page (at most 50) and the total.';

revoke all on function public.admin_search_questions_filtered(jsonb) from public, anon;
grant execute on function public.admin_search_questions_filtered(jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- Catalog. Deletes refuse while another row still points here.
-- ---------------------------------------------------------------------------

create or replace function public.admin_list_phases()
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
      'id', p.id,
      'code', p.code,
      'name', p.name,
      'display_order', p.display_order
    ) order by p.display_order, p.name)
    from public.mbbs_phases p
  ), '[]'::jsonb);
end;
$$;

create or replace function public.admin_list_universities()
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
      'id', u.id,
      'code', u.code,
      'name', u.name,
      'state', u.state,
      'slug', u.slug
    ) order by u.name)
    from public.universities u
  ), '[]'::jsonb);
end;
$$;

create or replace function public.admin_list_colleges(p_university_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.assert_admin();

  if p_university_id is null or not exists (
    select 1 from public.universities where id = p_university_id
  ) then
    raise exception 'Choose a university that already exists.';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', c.id,
      'university_id', c.university_id,
      'name', c.name,
      'short_form', c.short_form
    ) order by c.name)
    from public.colleges c
    where c.university_id = p_university_id
  ), '[]'::jsonb);
end;
$$;

create or replace function public.admin_list_subjects()
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
      'id', s.id,
      'name', s.name,
      'display_order', s.display_order,
      'mbbs_phase_id', s.mbbs_phase_id,
      'phase_code', p.code,
      'phase_name', p.name,
      'required_plan', s.required_plan
    ) order by s.display_order, s.name)
    from public.subjects s
    left join public.mbbs_phases p on p.id = s.mbbs_phase_id
  ), '[]'::jsonb);
end;
$$;

create or replace function public.admin_upsert_university(p_body jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid := nullif(p_body->>'id', '')::uuid;
  v_code text;
  v_name text := nullif(btrim(coalesce(p_body->>'name', '')), '');
  v_state text := nullif(btrim(coalesce(p_body->>'state', '')), '');
  v_slug text;
begin
  perform public.assert_admin();

  v_code := upper(regexp_replace(btrim(coalesce(p_body->>'code', '')), '[^A-Za-z0-9]', '', 'g'));
  if v_code !~ '^[A-Z0-9]{2,16}$' then
    raise exception 'University code must be 2–16 letters or digits.';
  end if;
  if v_name is null then
    raise exception 'Name is required.';
  end if;
  if char_length(v_name) > 200 then
    raise exception 'Name must be 200 characters or fewer.';
  end if;
  if v_state is null then
    raise exception 'State is required.';
  end if;
  if char_length(v_state) > 80 then
    raise exception 'State must be 80 characters or fewer.';
  end if;

  v_slug := trim(both '-' from regexp_replace(
    lower(btrim(coalesce(nullif(btrim(coalesce(p_body->>'slug', '')), ''), v_name))),
    '[^a-z0-9]+',
    '-',
    'g'
  ));
  if v_slug is null or v_slug = '' or v_slug !~ '^[a-z0-9]+(-[a-z0-9]+)*$' then
    raise exception 'Slug must be lowercase letters, numbers, and hyphens.';
  end if;

  if exists (
    select 1 from public.universities
    where upper(code) = v_code
      and id is distinct from v_id
  ) then
    raise exception 'That university code is already used.';
  end if;
  if exists (
    select 1 from public.universities
    where slug = v_slug
      and id is distinct from v_id
  ) then
    raise exception 'That slug is already used.';
  end if;

  if v_id is null then
    insert into public.universities (code, name, state, slug)
    values (v_code, v_name, v_state, v_slug)
    returning id into v_id;
  else
    if not exists (select 1 from public.universities where id = v_id) then
      raise exception 'University not found.';
    end if;
    update public.universities
    set code = v_code,
        name = v_name,
        state = v_state,
        slug = v_slug
    where id = v_id;
  end if;

  perform public.admin_log_action(
    'upsert_university',
    v_id,
    jsonb_build_object('code', v_code, 'name', v_name, 'state', v_state)
  );

  return jsonb_build_object(
    'id', v_id,
    'code', v_code,
    'name', v_name,
    'state', v_state,
    'slug', v_slug
  );
end;
$$;

create or replace function public.admin_delete_university(p_university_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.assert_admin();

  if p_university_id is null or not exists (
    select 1 from public.universities where id = p_university_id
  ) then
    raise exception 'University not found.';
  end if;
  if exists (
    select 1 from public.colleges where university_id = p_university_id
  ) then
    raise exception 'Remove this university''s colleges first.';
  end if;
  if exists (
    select 1 from public.exam_papers where university_id = p_university_id
  ) then
    raise exception 'This university is still used on a paper.';
  end if;
  if exists (
    select 1 from public.profiles where university_id = p_university_id
  ) then
    raise exception 'A student profile still uses this university.';
  end if;

  delete from public.universities where id = p_university_id;

  perform public.admin_log_action('delete_university', p_university_id, '{}'::jsonb);
  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.admin_upsert_college(p_body jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid := nullif(p_body->>'id', '')::uuid;
  v_university_id uuid := nullif(p_body->>'university_id', '')::uuid;
  v_name text := nullif(btrim(coalesce(p_body->>'name', '')), '');
  v_short text := nullif(btrim(coalesce(p_body->>'short_form', '')), '');
begin
  perform public.assert_admin();

  if v_university_id is null or not exists (
    select 1 from public.universities where id = v_university_id
  ) then
    raise exception 'Choose a university that already exists.';
  end if;
  if v_name is null then
    raise exception 'Name is required.';
  end if;
  if char_length(v_name) > 300 then
    raise exception 'Name must be 300 characters or fewer.';
  end if;
  if v_short is null or char_length(v_short) > 40 then
    raise exception 'Short form is required (40 characters or fewer).';
  end if;

  if exists (
    select 1
    from public.colleges
    where university_id = v_university_id
      and lower(name) = lower(v_name)
      and id is distinct from v_id
  ) then
    raise exception 'That college is already in this university.';
  end if;
  if exists (
    select 1
    from public.colleges
    where university_id = v_university_id
      and lower(short_form) = lower(v_short)
      and id is distinct from v_id
  ) then
    raise exception 'That short form is already used in this university.';
  end if;

  if v_id is null then
    insert into public.colleges (university_id, name, short_form)
    values (v_university_id, v_name, v_short)
    returning id into v_id;
  else
    if not exists (
      select 1 from public.colleges
      where id = v_id
        and university_id = v_university_id
    ) then
      raise exception 'College not found.';
    end if;
    update public.colleges
    set name = v_name,
        short_form = v_short
    where id = v_id;
  end if;

  perform public.admin_log_action(
    'upsert_college',
    v_id,
    jsonb_build_object('university_id', v_university_id, 'name', v_name, 'short_form', v_short)
  );

  return jsonb_build_object(
    'id', v_id,
    'university_id', v_university_id,
    'name', v_name,
    'short_form', v_short
  );
end;
$$;

create or replace function public.admin_delete_college(p_college_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.assert_admin();

  if p_college_id is null or not exists (
    select 1 from public.colleges where id = p_college_id
  ) then
    raise exception 'College not found.';
  end if;
  if exists (
    select 1 from public.exam_papers where college_id = p_college_id
  ) then
    raise exception 'This college is still used on a paper.';
  end if;
  if exists (
    select 1 from public.profiles where college_id = p_college_id
  ) then
    raise exception 'A student profile still uses this college.';
  end if;

  delete from public.colleges where id = p_college_id;

  perform public.admin_log_action('delete_college', p_college_id, '{}'::jsonb);
  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.admin_upsert_subject(p_body jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid := nullif(p_body->>'id', '')::uuid;
  v_name text := nullif(btrim(coalesce(p_body->>'name', '')), '');
  v_phase_id uuid := nullif(p_body->>'mbbs_phase_id', '')::uuid;
  v_plan text := lower(btrim(coalesce(nullif(p_body->>'required_plan', ''), 'free')));
  v_order int;
  v_old_name text;
  v_phase_code public.mbbs_phase_code;
begin
  perform public.assert_admin();

  if v_name is null then
    raise exception 'Name is required.';
  end if;
  if char_length(v_name) > 200 then
    raise exception 'Name must be 200 characters or fewer.';
  end if;
  if v_phase_id is null then
    raise exception 'Choose a year of MBBS.';
  end if;

  select code into v_phase_code
  from public.mbbs_phases
  where id = v_phase_id;
  if v_phase_code is null then
    raise exception 'Choose a year of MBBS that already exists.';
  end if;

  if v_plan not in ('free', 'pro', 'elite') then
    raise exception 'Pick a plan of free, pro, or elite.';
  end if;

  begin
    if nullif(btrim(coalesce(p_body->>'display_order', '')), '') is null then
      v_order := null;
    else
      v_order := (p_body->>'display_order')::int;
    end if;
  exception
    when invalid_text_representation or numeric_value_out_of_range then
      raise exception 'Display order must be a whole number.';
  end;

  if exists (
    select 1 from public.subjects
    where lower(name) = lower(v_name)
      and id is distinct from v_id
  ) then
    raise exception 'That subject name is already used.';
  end if;

  if v_id is null then
    if v_order is null then
      select coalesce(max(display_order), 0) + 1 into v_order
      from public.subjects;
    end if;
    insert into public.subjects (name, display_order, mbbs_phase_id, required_plan)
    values (v_name, v_order, v_phase_id, v_plan::public.plan_tier)
    returning id into v_id;
  else
    select name into v_old_name from public.subjects where id = v_id;
    if v_old_name is null then
      raise exception 'Subject not found.';
    end if;
    if v_order is null then
      select display_order into v_order from public.subjects where id = v_id;
    end if;
    update public.subjects
    set name = v_name,
        display_order = v_order,
        mbbs_phase_id = v_phase_id,
        required_plan = v_plan::public.plan_tier
    where id = v_id;

    if v_old_name is distinct from v_name then
      delete from public.subject_phase_defaults
      where subject_name = v_old_name;
    end if;
  end if;

  insert into public.subject_phase_defaults (subject_name, phase_code, display_order)
  values (v_name, v_phase_code, v_order)
  on conflict (subject_name) do update
    set phase_code = excluded.phase_code,
        display_order = excluded.display_order;

  perform public.admin_log_action(
    'upsert_subject',
    v_id,
    jsonb_build_object('name', v_name, 'required_plan', v_plan, 'phase', v_phase_code)
  );

  return jsonb_build_object(
    'id', v_id,
    'name', v_name,
    'display_order', v_order,
    'mbbs_phase_id', v_phase_id,
    'phase_code', v_phase_code,
    'required_plan', v_plan
  );
end;
$$;

create or replace function public.admin_delete_subject(p_subject_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text;
begin
  perform public.assert_admin();

  select name into v_name from public.subjects where id = p_subject_id;
  if v_name is null then
    raise exception 'Subject not found.';
  end if;
  if exists (
    select 1 from public.topics where subject_id = p_subject_id
  ) then
    raise exception 'This subject still has chapters. Remove those questions first.';
  end if;
  if exists (
    select 1 from public.exam_papers where subject_id = p_subject_id
  ) then
    raise exception 'This subject is still used on a paper.';
  end if;
  if exists (
    select 1 from public.tests where subject_id = p_subject_id
  ) then
    raise exception 'This subject is still used by a test.';
  end if;

  delete from public.subject_phase_defaults where subject_name = v_name;
  delete from public.subjects where id = p_subject_id;

  perform public.admin_log_action(
    'delete_subject',
    p_subject_id,
    jsonb_build_object('name', v_name)
  );
  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.admin_list_phases() from public, anon;
revoke all on function public.admin_list_universities() from public, anon;
revoke all on function public.admin_list_colleges(uuid) from public, anon;
revoke all on function public.admin_list_subjects() from public, anon;
revoke all on function public.admin_upsert_university(jsonb) from public, anon;
revoke all on function public.admin_delete_university(uuid) from public, anon;
revoke all on function public.admin_upsert_college(jsonb) from public, anon;
revoke all on function public.admin_delete_college(uuid) from public, anon;
revoke all on function public.admin_upsert_subject(jsonb) from public, anon;
revoke all on function public.admin_delete_subject(uuid) from public, anon;

grant execute on function public.admin_list_phases() to authenticated;
grant execute on function public.admin_list_universities() to authenticated;
grant execute on function public.admin_list_colleges(uuid) to authenticated;
grant execute on function public.admin_list_subjects() to authenticated;
grant execute on function public.admin_upsert_university(jsonb) to authenticated;
grant execute on function public.admin_delete_university(uuid) to authenticated;
grant execute on function public.admin_upsert_college(jsonb) to authenticated;
grant execute on function public.admin_delete_college(uuid) to authenticated;
grant execute on function public.admin_upsert_subject(jsonb) to authenticated;
grant execute on function public.admin_delete_subject(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Users: grant or remove admin. You cannot remove your own flag.
-- ---------------------------------------------------------------------------

create or replace function public.admin_set_admin(
  p_user_id uuid,
  p_is_admin boolean
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.assert_admin();

  if p_is_admin is null then
    raise exception 'Say whether this account is an admin.';
  end if;
  if not exists (select 1 from public.profiles where id = p_user_id) then
    raise exception 'User not found.';
  end if;
  if p_user_id = auth.uid() and not p_is_admin then
    raise exception 'You cannot remove your own admin access.';
  end if;

  update public.profiles
  set is_admin = p_is_admin
  where id = p_user_id;

  perform public.admin_log_action(
    'set_admin',
    p_user_id,
    jsonb_build_object('is_admin', p_is_admin)
  );

  return public.admin_user_json(p_user_id);
end;
$$;

comment on function public.admin_set_admin(uuid, boolean) is
  'Sets profiles.is_admin. Refuses to clear the caller''s own flag.';

revoke all on function public.admin_set_admin(uuid, boolean) from public, anon;
grant execute on function public.admin_set_admin(uuid, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- Plan prices. Duration months stay as they are. Checkout reads this table.
-- ---------------------------------------------------------------------------

create or replace function public.admin_list_plan_prices()
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
      'plan', c.plan,
      'period', c.period,
      'amount_paise', c.amount_paise,
      'duration_months', c.duration_months
    ) order by c.plan, c.period)
    from public.paid_plan_catalog c
  ), '[]'::jsonb);
end;
$$;

create or replace function public.admin_set_plan_price(
  p_plan text,
  p_period text,
  p_amount_paise integer
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_plan text := lower(btrim(coalesce(p_plan, '')));
  v_period text := lower(btrim(coalesce(p_period, '')));
  v_old integer;
begin
  perform public.assert_admin();

  if v_plan not in ('pro', 'elite') then
    raise exception 'Pick a plan of pro or elite.';
  end if;
  if v_period not in ('y1', 'y2', 'y3', 'y4') then
    raise exception 'Pick a period of y1, y2, y3, or y4.';
  end if;
  if p_amount_paise is null or p_amount_paise < 100 then
    raise exception 'Price must be at least ₹1.';
  end if;

  select amount_paise into v_old
  from public.paid_plan_catalog
  where plan = v_plan::public.plan_tier
    and period = v_period;

  if v_old is null then
    raise exception 'That plan period is not in the catalog.';
  end if;

  update public.paid_plan_catalog
  set amount_paise = p_amount_paise
  where plan = v_plan::public.plan_tier
    and period = v_period;

  perform public.admin_log_action(
    'set_plan_price',
    null,
    jsonb_build_object(
      'plan', v_plan,
      'period', v_period,
      'amount_paise', p_amount_paise,
      'previous_amount_paise', v_old
    )
  );

  return jsonb_build_object(
    'plan', v_plan,
    'period', v_period,
    'amount_paise', p_amount_paise
  );
end;
$$;

revoke all on function public.admin_list_plan_prices() from public, anon;
revoke all on function public.admin_set_plan_price(text, text, integer) from public, anon;
grant execute on function public.admin_list_plan_prices() to authenticated;
grant execute on function public.admin_set_plan_price(text, text, integer) to authenticated;

-- ---------------------------------------------------------------------------
-- Percent-off codes. issue_discount_code stays service_role only.
-- ---------------------------------------------------------------------------

create or replace function public.admin_list_discount_codes()
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
      'id', d.id,
      'code', d.code,
      'percent_off', d.percent_off,
      'owner_user_id', d.owner_user_id,
      'owner_name', p.full_name,
      'max_redemptions', d.max_redemptions,
      'redemption_count', d.redemption_count,
      'expires_at', d.expires_at,
      'active', d.active,
      'created_at', d.created_at
    ) order by d.created_at desc)
    from public.discount_codes d
    left join public.profiles p on p.id = d.owner_user_id
  ), '[]'::jsonb);
end;
$$;

create or replace function public.admin_create_discount_code(
  p_percent_off integer,
  p_code text default null,
  p_max_redemptions integer default null,
  p_expires_at timestamptz default null,
  p_owner_user_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
  v_id uuid;
begin
  perform public.assert_admin();

  v_code := public.issue_discount_code(
    p_percent_off,
    p_owner_user_id,
    nullif(btrim(coalesce(p_code, '')), ''),
    p_max_redemptions,
    p_expires_at
  );

  select id into v_id
  from public.discount_codes
  where code = v_code;

  perform public.admin_log_action(
    'create_discount_code',
    v_id,
    jsonb_build_object(
      'code', v_code,
      'percent_off', p_percent_off,
      'owner_user_id', p_owner_user_id,
      'max_redemptions', p_max_redemptions,
      'expires_at', p_expires_at
    )
  );

  return jsonb_build_object('id', v_id, 'code', v_code);
end;
$$;

create or replace function public.admin_set_discount_active(
  p_code text,
  p_active boolean
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text := public.normalize_discount_code(p_code);
  v_id uuid;
begin
  perform public.assert_admin();

  if p_active is null then
    raise exception 'Say whether this code is active.';
  end if;
  if v_code is null then
    raise exception 'Code must be 4–16 letters or digits.';
  end if;

  update public.discount_codes
  set active = p_active
  where code = v_code
  returning id into v_id;

  if v_id is null then
    raise exception 'Code not found.';
  end if;

  perform public.admin_log_action(
    'set_discount_active',
    v_id,
    jsonb_build_object('code', v_code, 'active', p_active)
  );

  return jsonb_build_object('id', v_id, 'code', v_code, 'active', p_active);
end;
$$;

comment on function public.admin_create_discount_code(integer, text, integer, timestamptz, uuid) is
  'Admin wrapper around issue_discount_code. A blank code is generated. An owner makes it a referral.';

revoke all on function public.admin_list_discount_codes() from public, anon;
revoke all on function public.admin_create_discount_code(integer, text, integer, timestamptz, uuid) from public, anon;
revoke all on function public.admin_set_discount_active(text, boolean) from public, anon;
grant execute on function public.admin_list_discount_codes() to authenticated;
grant execute on function public.admin_create_discount_code(integer, text, integer, timestamptz, uuid) to authenticated;
grant execute on function public.admin_set_discount_active(text, boolean) to authenticated;
