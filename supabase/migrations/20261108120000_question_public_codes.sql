-- Six-digit question ids. The same wording can be more than one question.
-- question_id on the sheet is questions.public_code. Rows that share a code
-- are one question with several appearances. A blank code is a new question.

alter table public.questions
  add column if not exists public_code text;

alter table public.questions
  drop constraint if exists questions_public_code_format;

alter table public.questions
  add constraint questions_public_code_format
  check (public_code is null or public_code ~ '^[0-9]{6}$');

create unique index if not exists questions_public_code_key
  on public.questions (public_code);

comment on column public.questions.public_code is
  'Stable six-digit id shown in the app and the Questions sheet (question_id). Not derived from the stem.';

create sequence if not exists public.question_public_code_seq as integer;

do $$
declare
  v_start int;
begin
  if (select count(*) from public.questions where public_code is null) > 999999 then
    raise exception 'Too many questions to assign six-digit ids';
  end if;

  select coalesce(max(public_code::int), 0)
    into v_start
  from public.questions
  where public_code ~ '^[0-9]{6}$';

  with numbered as (
    select id,
      row_number() over (order by created_at, id) + v_start as n
    from public.questions
    where public_code is null
  )
  update public.questions q
  set public_code = lpad(numbered.n::text, 6, '0')
  from numbered
  where q.id = numbered.id;

  perform setval(
    'public.question_public_code_seq',
    greatest(
      1,
      coalesce((select max(public_code::int) from public.questions where public_code ~ '^[0-9]{6}$'), 1)
    ),
    exists (select 1 from public.questions where public_code is not null)
  );
end $$;

revoke all on sequence public.question_public_code_seq from public, anon, authenticated;

create or replace function public.sheet_marks_text(p_marks numeric)
returns text
language sql
immutable
as $$
  select case
    when p_marks is null then ''
    else regexp_replace(trim(to_char(p_marks, 'FM999990.99')), '\.$', '')
  end;
$$;

create or replace function public.question_body_fingerprint(
  p_chapter text,
  p_topic text,
  p_marks text,
  p_option_a text,
  p_option_b text,
  p_option_c text,
  p_option_d text,
  p_correct text,
  p_exp_1 text,
  p_exp_2 text,
  p_answer text
) returns text
language sql
immutable
as $$
  select concat_ws('|',
    coalesce(p_chapter, ''),
    coalesce(p_topic, ''),
    coalesce(p_marks, ''),
    coalesce(p_option_a, ''),
    coalesce(p_option_b, ''),
    coalesce(p_option_c, ''),
    coalesce(p_option_d, ''),
    coalesce(p_correct, ''),
    coalesce(p_exp_1, ''),
    coalesce(p_exp_2, ''),
    coalesce(p_answer, '')
  );
$$;

create or replace function public.allocate_question_public_code()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  n int;
  code text;
begin
  loop
    n := nextval('public.question_public_code_seq');
    if n > 999999 then
      raise exception 'Question ids are exhausted at 999999.';
    end if;
    code := lpad(n::text, 6, '0');
    exit when not exists (
      select 1
      from public.questions q
      where q.public_code = code
         or q.external_id = code
    );
  end loop;
  return code;
end;
$$;

revoke all on function public.sheet_marks_text(numeric) from public, anon, authenticated;
revoke all on function public.question_body_fingerprint(text, text, text, text, text, text, text, text, text, text, text) from public, anon, authenticated;
revoke all on function public.allocate_question_public_code() from public, anon, authenticated;


create or replace function public.sync_content_csv(
  p_rows jsonb,
  p_apply boolean default false
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_source constant text := 'questions_csv_v2';
  v_errors jsonb := '[]'::jsonb;
  v_warnings jsonb := '[]'::jsonb;
  v_row jsonb;
  v_row_no int := 2;
  v_kind text;
  v_subject text;
  v_stem text;
  v_year text;
  v_month smallint;
  v_paper text;
  v_alias text;
  v_uni_name text;
  v_sheet_uni_name text;
  v_state text;
  v_uni_state text;
  v_college_alias text;
  v_college_name text;
  v_exam_type text;
  v_marks text;
  v_page text;
  v_tb_title text;
  v_resource_title text;
  v_resource_url text;
  v_question_inserts int := 0;
  v_question_updates int := 0;
  v_question_deletes int := 0;
  v_dependent_deletes int := 0;
  v_attempt_deletes int := 0;
  v_answer_deletes int := 0;
  v_question_id uuid;
  v_subject_id uuid;
  v_topic_id uuid;
  v_lesson_id uuid;
  v_university_id uuid;
  v_college_id uuid;
  v_paper_id uuid;
  v_textbook_id uuid;
  v_external_id text;
  v_paper_external_id text;
  v_textbook_key text;
  v_key text;
  v_chapter text;
  v_topic text;
  v_public_code text;
  v_raw_code text;
  v_legacy_id text;
  v_body_fp text;
  v_next_code int := 0;
  v_assigned jsonb := '[]'::jsonb;
  v_candidate_count int;
  v_group_count int;
  v_code_on_sheet boolean;
  v_adopt_id uuid;
  v_adopt_code text;
  v_stored_fp text;
  v_match_count int;
  v_grp record;
  v_allowed_columns text[] := array[
    '_row_number', 'course', 'state',
    'university_alias', 'university_name',
    'college_alias', 'college_name',
    'exam_type', 'year', 'month', 'paper_number',
    'subject_name', 'chapter_name', 'topic_name',
    'question_type', 'marks', 'question_text',
    'option_a', 'option_b', 'option_c', 'option_d', 'correct_option',
    'question_id', 'answers', 'exp_1', 'exp_2',
    'textbook_title', 'textbook_authors', 'textbook_edition',
    'page', 'section_heading', 'difficulty', 'required_plan', 'is_active',
    'resource_title', 'resource_url', 'resource_source_label', 'resource_is_free'
  ];
  v_rec record;
begin
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    return jsonb_build_object(
      'ok', false,
      'applied', false,
      'errors', jsonb_build_array('Input must be a JSON array of CSV rows.'),
      'warnings', v_warnings
    );
  end if;
  if jsonb_array_length(p_rows) = 0 then
    return jsonb_build_object(
      'ok', false,
      'applied', false,
      'errors', jsonb_build_array('Questions CSV has no content rows; refusing to delete the complete catalog.'),
      'warnings', v_warnings
    );
  end if;

  drop table if exists pg_temp.tmp_content_rows;
  drop table if exists pg_temp.tmp_stale_questions;
  drop table if exists pg_temp.tmp_affected_attempts;
  drop table if exists pg_temp.tmp_stem_candidates;
  drop table if exists pg_temp.tmp_blank_groups;
  create temporary table tmp_content_rows (
    row_no int not null,
    external_id text not null,
    legacy_external_id text,
    public_code text,
    adopt_question_id uuid,
    body_fp text,
    subject_name text not null,
    question_text text not null,
    kind text not null,
    option_a text,
    option_b text,
    option_c text,
    option_d text,
    correct_option text,
    chapter_name text,
    topic_name text,
    marks text,
    university_id uuid,
    college_id uuid,
    exam_year text,
    exam_month int,
    paper_name text,
    exam_type text,
    textbook_title text,
    textbook_authors text,
    textbook_edition text,
    page text,
    section_heading text,
    explanation_text text,
    explanation_deep text,
    sample_answer_text text,
    difficulty text,
    required_plan text,
    is_active text,
    resource_title text,
    resource_url text,
    resource_source_label text,
    resource_is_free text
  ) on commit drop;

  for v_row in select value from jsonb_array_elements(p_rows)
  loop
    if coalesce(v_row->>'_row_number', '') ~ '^[0-9]+$' then
      v_row_no := (v_row->>'_row_number')::int;
    end if;
    for v_key in select jsonb_object_keys(v_row)
    loop
      if not (v_key = any(v_allowed_columns)) then
        v_errors := v_errors || jsonb_build_array(
          'Questions row ' || v_row_no || ': unsupported column "' || v_key ||
          '". Use the current Questions.csv template.'
        );
      end if;
    end loop;

    v_subject := btrim(coalesce(v_row->>'subject_name', ''));
    v_stem := btrim(coalesce(v_row->>'question_text', ''));
    v_kind := lower(btrim(coalesce(v_row->>'question_type', '')));
    v_alias := btrim(coalesce(v_row->>'university_alias', ''));
    v_sheet_uni_name := btrim(coalesce(v_row->>'university_name', ''));
    v_state := btrim(coalesce(v_row->>'state', ''));
    v_college_alias := btrim(coalesce(v_row->>'college_alias', ''));
    v_college_name := btrim(coalesce(v_row->>'college_name', ''));
    v_year := btrim(coalesce(v_row->>'year', ''));
    v_paper := btrim(coalesce(v_row->>'paper_number', ''));
    v_chapter := btrim(coalesce(v_row->>'chapter_name', ''));
    v_topic := btrim(coalesce(v_row->>'topic_name', ''));
    v_exam_type := public.normalize_sheet_exam_type(v_row->>'exam_type');
    v_month := public.normalize_sheet_exam_month(v_row->>'month');
    v_university_id := null;
    v_college_id := null;
    v_uni_name := null;
    v_uni_state := null;

    if v_subject = '' then
      v_errors := v_errors || jsonb_build_array('Questions row ' || v_row_no || ': subject_name is required');
    end if;
    if v_stem = '' then
      v_errors := v_errors || jsonb_build_array('Questions row ' || v_row_no || ': question_text is required');
    end if;
    if v_kind = '' then
      v_errors := v_errors || jsonb_build_array('Questions row ' || v_row_no || ': question_type is required');
    elsif v_kind not in ('mcq', 'pyq_theory') then
      v_errors := v_errors || jsonb_build_array('Questions row ' || v_row_no || ': question_type must be pyq_theory or mcq');
    end if;

    if v_kind = 'mcq' then
      if btrim(coalesce(v_row->>'option_a', '')) = '' then
        v_errors := v_errors || jsonb_build_array('Questions row ' || v_row_no || ': option_a is required for mcq');
      end if;
      if btrim(coalesce(v_row->>'option_b', '')) = '' then
        v_errors := v_errors || jsonb_build_array('Questions row ' || v_row_no || ': option_b is required for mcq');
      end if;
      if btrim(coalesce(v_row->>'option_c', '')) = '' then
        v_errors := v_errors || jsonb_build_array('Questions row ' || v_row_no || ': option_c is required for mcq');
      end if;
      if btrim(coalesce(v_row->>'option_d', '')) = '' then
        v_errors := v_errors || jsonb_build_array('Questions row ' || v_row_no || ': option_d is required for mcq');
      end if;
      if upper(btrim(coalesce(v_row->>'correct_option', ''))) not in ('A', 'B', 'C', 'D') then
        v_errors := v_errors || jsonb_build_array('Questions row ' || v_row_no || ': correct_option must be A, B, C, or D');
      end if;
    elsif v_kind = 'pyq_theory' and concat_ws('',
      btrim(coalesce(v_row->>'option_a', '')),
      btrim(coalesce(v_row->>'option_b', '')),
      btrim(coalesce(v_row->>'option_c', '')),
      btrim(coalesce(v_row->>'option_d', '')),
      btrim(coalesce(v_row->>'correct_option', ''))
    ) <> '' then
      v_errors := v_errors || jsonb_build_array('Questions row ' || v_row_no || ': pyq_theory rows must leave option and correct_option cells blank');
    end if;

    if v_topic <> '' and v_chapter = '' then
      v_errors := v_errors || jsonb_build_array('Questions row ' || v_row_no || ': topic_name requires chapter_name');
    end if;

    if v_alias = '' then
      v_errors := v_errors || jsonb_build_array('Questions row ' || v_row_no || ': university_alias is required');
    end if;
    if v_sheet_uni_name = '' then
      v_errors := v_errors || jsonb_build_array('Questions row ' || v_row_no || ': university_name is required');
    end if;
    if v_alias <> '' then
      select u.id, u.name, u.state
        into v_university_id, v_uni_name, v_uni_state
      from public.universities u
      where lower(u.code) = lower(v_alias)
      order by u.id
      limit 1;
      if v_university_id is null then
        v_errors := v_errors || jsonb_build_array(
          'Questions row ' || v_row_no || ': university_alias "' || v_alias || '" does not exist'
        );
      elsif v_sheet_uni_name <> '' and lower(regexp_replace(v_uni_name, '\s+', ' ', 'g'))
            is distinct from lower(regexp_replace(v_sheet_uni_name, '\s+', ' ', 'g')) then
        v_university_id := null;
        v_errors := v_errors || jsonb_build_array(
          'Questions row ' || v_row_no || ': university_name does not match university_alias "' || v_alias || '"'
        );
      elsif v_state <> '' and lower(regexp_replace(coalesce(v_uni_state, ''), '\s+', ' ', 'g'))
            is distinct from lower(regexp_replace(v_state, '\s+', ' ', 'g')) then
        v_errors := v_errors || jsonb_build_array(
          'Questions row ' || v_row_no || ': state does not match the university'
        );
      end if;
    end if;

    if (v_college_alias = '') <> (v_college_name = '') then
      v_errors := v_errors || jsonb_build_array(
        'Questions row ' || v_row_no || ': college_alias and college_name must be filled together'
      );
    elsif v_college_alias <> '' and v_university_id is not null then
      select c.id into v_college_id
      from public.colleges c
      where c.university_id = v_university_id
        and lower(c.short_form) = lower(v_college_alias)
        and lower(regexp_replace(c.name, '\s+', ' ', 'g'))
            = lower(regexp_replace(v_college_name, '\s+', ' ', 'g'))
      order by c.id
      limit 1;
      if v_college_id is null then
        v_errors := v_errors || jsonb_build_array(
          'Questions row ' || v_row_no || ': college_alias and college_name do not match a college for this university'
        );
      end if;
    end if;

    if btrim(coalesce(v_row->>'exam_type', '')) = '' then
      v_errors := v_errors || jsonb_build_array('Questions row ' || v_row_no || ': exam_type is required');
    elsif v_exam_type is null then
      v_errors := v_errors || jsonb_build_array(
        'Questions row ' || v_row_no || ': exam_type must be PROF, SUPPLY, PRE PROF, or INTERNAL'
      );
    end if;

    if v_year = '' then
      v_errors := v_errors || jsonb_build_array('Questions row ' || v_row_no || ': year is required');
    elsif v_year !~ '^[0-9]{4}(\.0+)?$' then
      v_errors := v_errors || jsonb_build_array('Questions row ' || v_row_no || ': year must be a four-digit year');
      v_year := '';
    else
      v_year := split_part(v_year, '.', 1);
      if v_year::int < 1900 or v_year::int > 2200 then
        v_errors := v_errors || jsonb_build_array('Questions row ' || v_row_no || ': year must be between 1900 and 2200');
      end if;
    end if;

    if btrim(coalesce(v_row->>'month', '')) = '' then
      v_errors := v_errors || jsonb_build_array('Questions row ' || v_row_no || ': month is required');
    elsif v_month is null then
      v_errors := v_errors || jsonb_build_array(
        'Questions row ' || v_row_no || ': month must be a month name such as May or June'
      );
    end if;

    if v_subject <> '' and not exists (
      select 1 from public.subjects s
      where lower(s.name) = lower(v_subject)
    ) then
      v_errors := v_errors || jsonb_build_array(
        'Questions row ' || v_row_no || ': subject_name "' || v_subject || '" is not in subjects'
      );
    end if;

    v_marks := btrim(coalesce(v_row->>'marks', ''));
    if v_marks ~ '^[0-9]+(\.0+)?$' then
      v_marks := split_part(v_marks, '.', 1);
    end if;
    if v_marks <> '' then
      if v_marks !~ '^[0-9]+([.][0-9]+)?$' then
        v_errors := v_errors || jsonb_build_array('Questions row ' || v_row_no || ': marks must be a positive number');
      elsif v_marks::numeric <= 0 then
        v_errors := v_errors || jsonb_build_array('Questions row ' || v_row_no || ': marks must be greater than zero');
      end if;
    end if;

    v_tb_title := btrim(coalesce(v_row->>'textbook_title', ''));
    v_page := btrim(coalesce(v_row->>'page', ''));
    if (v_tb_title = '') <> (v_page = '') then
      v_errors := v_errors || jsonb_build_array('Questions row ' || v_row_no || ': textbook_title and page must be filled together');
    end if;
    if v_page <> '' then
      if v_page !~ '^[0-9]+$' then
        v_errors := v_errors || jsonb_build_array('Questions row ' || v_row_no || ': page must be a positive integer');
      elsif v_page::int <= 0 then
        v_errors := v_errors || jsonb_build_array('Questions row ' || v_row_no || ': page must be greater than zero');
      end if;
    end if;

    v_resource_title := btrim(coalesce(v_row->>'resource_title', ''));
    v_resource_url := btrim(coalesce(v_row->>'resource_url', ''));
    if (v_resource_title = '') <> (v_resource_url = '') then
      v_errors := v_errors || jsonb_build_array('Questions row ' || v_row_no || ': resource_title and resource_url must be filled together');
    end if;
    if v_resource_url <> '' and v_resource_url !~ '^https://' then
      v_errors := v_errors || jsonb_build_array('Questions row ' || v_row_no || ': resource_url must start with https://');
    end if;

    if lower(coalesce(nullif(btrim(coalesce(v_row->>'difficulty', '')), ''), 'should')) not in ('must', 'should', 'could') then
      v_errors := v_errors || jsonb_build_array('Questions row ' || v_row_no || ': difficulty must be must, should, or could (blank = should)');
    end if;
    if lower(coalesce(nullif(btrim(coalesce(v_row->>'required_plan', '')), ''), 'free')) not in ('free', 'pro', 'elite') then
      v_errors := v_errors || jsonb_build_array('Questions row ' || v_row_no || ': required_plan must be free, pro, or elite');
    end if;
    if upper(coalesce(nullif(btrim(coalesce(v_row->>'is_active', '')), ''), 'TRUE')) not in ('TRUE', 'FALSE', 'YES', 'NO', '1', '0') then
      v_errors := v_errors || jsonb_build_array('Questions row ' || v_row_no || ': is_active must be TRUE or FALSE');
    end if;
    if upper(coalesce(nullif(btrim(coalesce(v_row->>'resource_is_free', '')), ''), 'TRUE')) not in ('TRUE', 'FALSE', 'YES', 'NO', '1', '0') then
      v_errors := v_errors || jsonb_build_array('Questions row ' || v_row_no || ': resource_is_free must be TRUE or FALSE');
    end if;

    v_legacy_id := public.admin_question_external_id(v_subject, nullif(v_kind, ''), v_stem);
    v_public_code := null;
    v_raw_code := btrim(coalesce(v_row->>'question_id', ''));
    if v_raw_code ~ '^[0-9]+(\.0+)?$' then
      v_raw_code := split_part(v_raw_code, '.', 1);
    end if;
    if v_raw_code <> '' then
      if v_raw_code !~ '^[0-9]{1,6}$' or v_raw_code::int = 0 then
        v_errors := v_errors || jsonb_build_array(
          'Questions row ' || v_row_no || ': question_id must be a number from 1 to 999999'
        );
      else
        v_public_code := lpad(v_raw_code, 6, '0');
      end if;
    end if;
    v_body_fp := public.question_body_fingerprint(
      nullif(v_chapter, ''),
      nullif(v_topic, ''),
      nullif(v_marks, ''),
      nullif(btrim(coalesce(v_row->>'option_a', '')), ''),
      nullif(btrim(coalesce(v_row->>'option_b', '')), ''),
      nullif(btrim(coalesce(v_row->>'option_c', '')), ''),
      nullif(btrim(coalesce(v_row->>'option_d', '')), ''),
      nullif(upper(btrim(coalesce(v_row->>'correct_option', ''))), ''),
      nullif(btrim(coalesce(v_row->>'exp_1', '')), ''),
      nullif(btrim(coalesce(v_row->>'exp_2', '')), ''),
      nullif(btrim(coalesce(v_row->>'answers', '')), '')
    );

    insert into tmp_content_rows (
      row_no, external_id, legacy_external_id, public_code, body_fp,
      subject_name, question_text, kind,
      option_a, option_b, option_c, option_d, correct_option,
      chapter_name, topic_name, marks,
      university_id, college_id, exam_year, exam_month, paper_name, exam_type,
      textbook_title, textbook_authors, textbook_edition, page, section_heading,
      explanation_text, explanation_deep, sample_answer_text,
      difficulty, required_plan, is_active,
      resource_title, resource_url, resource_source_label, resource_is_free
    ) values (
      v_row_no, coalesce(v_public_code, v_legacy_id), v_legacy_id, v_public_code, v_body_fp,
      coalesce(nullif(v_subject, ''), '(missing)'), coalesce(nullif(v_stem, ''), '(missing)'),
      coalesce(nullif(v_kind, ''), 'pyq_theory'),
      nullif(btrim(coalesce(v_row->>'option_a', '')), ''),
      nullif(btrim(coalesce(v_row->>'option_b', '')), ''),
      nullif(btrim(coalesce(v_row->>'option_c', '')), ''),
      nullif(btrim(coalesce(v_row->>'option_d', '')), ''),
      nullif(upper(btrim(coalesce(v_row->>'correct_option', ''))), ''),
      nullif(v_chapter, ''), nullif(v_topic, ''), nullif(v_marks, ''),
      v_university_id, v_college_id, nullif(v_year, ''), v_month, nullif(v_paper, ''), v_exam_type,
      nullif(v_tb_title, ''),
      nullif(btrim(coalesce(v_row->>'textbook_authors', '')), ''),
      nullif(btrim(coalesce(v_row->>'textbook_edition', '')), ''),
      nullif(v_page, ''),
      nullif(btrim(coalesce(v_row->>'section_heading', '')), ''),
      nullif(btrim(coalesce(v_row->>'exp_1', '')), ''),
      nullif(btrim(coalesce(v_row->>'exp_2', '')), ''),
      nullif(btrim(coalesce(v_row->>'answers', '')), ''),
      lower(coalesce(nullif(btrim(coalesce(v_row->>'difficulty', '')), ''), 'should')),
      lower(coalesce(nullif(btrim(coalesce(v_row->>'required_plan', '')), ''), 'free')),
      upper(coalesce(nullif(btrim(coalesce(v_row->>'is_active', '')), ''), 'TRUE')),
      nullif(v_resource_title, ''), nullif(v_resource_url, ''),
      nullif(btrim(coalesce(v_row->>'resource_source_label', '')), ''),
      upper(coalesce(nullif(btrim(coalesce(v_row->>'resource_is_free', '')), ''), 'TRUE'))
    );
    v_row_no := v_row_no + 1;
  end loop;

  -- Blank question_id values become a six-digit code. The same code is one
  -- question (another year is another appearance). A blank code is a new
  -- question even when the stem matches, unless this sheet has not been given
  -- codes yet and the row still belongs to the existing question.
  select coalesce(max(public_code::int), 0)
    into v_next_code
  from (
    select public_code from public.questions
    where public_code ~ '^[0-9]{6}$'
    union all
    select public_code from tmp_content_rows
    where public_code ~ '^[0-9]{6}$'
  ) used;

  create temporary table tmp_blank_groups on commit drop as
  select legacy_external_id, body_fp, min(row_no) as first_row
  from tmp_content_rows
  where public_code is null
  group by legacy_external_id, body_fp;

  create temporary table tmp_stem_candidates on commit drop as
  select
    q.id,
    q.public_code,
    q.external_id,
    public.admin_question_external_id(
      public.admin_question_subject_name(q.id),
      q.kind::text,
      q.question_text
    ) as legacy_external_id,
    public.question_body_fingerprint(
      nullif(btrim(top.name), ''),
      nullif(btrim(les.name), ''),
      nullif(public.sheet_marks_text(q.marks), ''),
      q.option_a, q.option_b, q.option_c, q.option_d, q.correct_option,
      nullif(btrim(q.explanation_text), ''),
      nullif(btrim(q.explanation_deep), ''),
      nullif(btrim(sa.body), '')
    ) as body_fp
  from public.questions q
  left join public.topics top on top.id = q.topic_id
  left join public.lessons les on les.id = q.lesson_id
  left join public.question_sample_answers sa on sa.question_id = q.id
  where q.content_sync_source = v_source
     or q.external_id like 'CSV-%';

  for v_grp in
    select * from tmp_blank_groups order by first_row
  loop
    v_adopt_id := null;
    v_adopt_code := null;
    v_stored_fp := null;
    v_code_on_sheet := false;
    v_match_count := null;

    select count(*)::int,
           coalesce(bool_or(
             c.public_code is not null
             and exists (
               select 1 from tmp_content_rows t
               where t.public_code = c.public_code
             )
           ), false)
      into v_candidate_count, v_code_on_sheet
    from tmp_stem_candidates c
    where c.legacy_external_id = v_grp.legacy_external_id
       or c.external_id = v_grp.legacy_external_id;

    select count(*)::int into v_group_count
    from tmp_blank_groups g
    where g.legacy_external_id = v_grp.legacy_external_id;

    if v_candidate_count = 1 and not v_code_on_sheet then
      select c.id, c.public_code, c.body_fp
        into v_adopt_id, v_adopt_code, v_stored_fp
      from tmp_stem_candidates c
      where c.legacy_external_id = v_grp.legacy_external_id
         or c.external_id = v_grp.legacy_external_id
      limit 1;

      if v_group_count > 1
         and v_stored_fp is distinct from v_grp.body_fp
         and exists (
           select 1 from tmp_blank_groups g
           where g.legacy_external_id = v_grp.legacy_external_id
             and g.body_fp is not distinct from v_stored_fp
         )
      then
        v_adopt_id := null;
        v_adopt_code := null;
      elsif v_group_count > 1
         and v_stored_fp is distinct from v_grp.body_fp
         and v_grp.first_row is distinct from (
           select min(g.first_row) from tmp_blank_groups g
           where g.legacy_external_id = v_grp.legacy_external_id
         )
         and not exists (
           select 1 from tmp_blank_groups g
           where g.legacy_external_id = v_grp.legacy_external_id
             and g.body_fp is not distinct from v_stored_fp
         )
      then
        v_adopt_id := null;
        v_adopt_code := null;
      end if;
    elsif v_candidate_count > 1 and not v_code_on_sheet then
      select count(*)::int into v_match_count
      from tmp_stem_candidates c
      where (c.legacy_external_id = v_grp.legacy_external_id
             or c.external_id = v_grp.legacy_external_id)
        and c.body_fp is not distinct from v_grp.body_fp
        and not exists (
          select 1 from tmp_content_rows t
          where t.public_code = c.public_code
            and c.public_code is not null
        );

      if v_match_count = 1 then
        select c.id, c.public_code
          into v_adopt_id, v_adopt_code
        from tmp_stem_candidates c
        where (c.legacy_external_id = v_grp.legacy_external_id
               or c.external_id = v_grp.legacy_external_id)
          and c.body_fp is not distinct from v_grp.body_fp
        limit 1;
      else
        v_errors := v_errors || jsonb_build_array(
          'Questions row ' || v_grp.first_row ||
          ': this stem matches more than one question; set question_id'
        );
      end if;
    end if;

    -- A blank id adopts an existing question only when that question is not
    -- already represented by a question_id on this sheet. Otherwise, and for
    -- a stem the database has never seen, allocate the next code.
    if v_adopt_code is null
       and not (
         v_candidate_count > 1
         and not v_code_on_sheet
         and v_match_count is distinct from 1
       )
    then
      if v_next_code >= 999999 then
        v_errors := v_errors || jsonb_build_array(
          'Questions row ' || v_grp.first_row || ': question ids are exhausted at 999999'
        );
      else
        v_next_code := v_next_code + 1;
        v_adopt_code := lpad(v_next_code::text, 6, '0');
      end if;
    end if;

    if v_adopt_code is not null then
      update tmp_content_rows
      set public_code = v_adopt_code,
          adopt_question_id = v_adopt_id,
          external_id = v_adopt_code
      where public_code is null
        and legacy_external_id = v_grp.legacy_external_id
        and body_fp is not distinct from v_grp.body_fp;

      if v_adopt_id is not null then
        update tmp_stem_candidates
        set public_code = v_adopt_code
        where id = v_adopt_id;
      end if;
    end if;
  end loop;

  update tmp_content_rows
  set external_id = public_code
  where public_code is not null;

  -- question_id is the only identity. Rows that share it are one question
  -- even when chapter, topic, marks, options, or explanations differ.
  -- distinct on (external_id) below keeps a single body for that id.

  for v_rec in
    select r.public_code, min(r.row_no) as first_row
    from tmp_content_rows r
    join public.questions q
      on q.external_id = r.public_code
      or q.public_code = r.public_code
    where r.public_code is not null
      and q.content_sync_source is distinct from v_source
      and q.id is distinct from r.adopt_question_id
    group by r.public_code
  loop
    v_errors := v_errors || jsonb_build_array(
      'Questions row ' || v_rec.first_row || ': question_id ' || v_rec.public_code ||
      ' belongs to content this sheet does not manage'
    );
  end loop;

  select count(*) filter (where q.id is null),
         count(*) filter (where q.id is not null)
    into v_question_inserts, v_question_updates
  from (
    select distinct public_code, adopt_question_id
    from tmp_content_rows
    where public_code is not null
  ) r
  left join lateral (
    select q.id
    from public.questions q
    where q.id = r.adopt_question_id
       or q.public_code = r.public_code
       or q.external_id = r.public_code
    limit 1
  ) q on true;

  select count(*) into v_question_deletes
  from public.questions q
  where q.content_sync_source = v_source
    and not exists (
      select 1 from tmp_content_rows r
      where r.public_code = q.public_code
         or r.public_code = q.external_id
         or r.adopt_question_id = q.id
    );

  create temporary table tmp_stale_questions on commit drop as
  select q.id
  from public.questions q
  where q.content_sync_source = v_source
    and not exists (
      select 1 from tmp_content_rows r
      where r.public_code = q.public_code
         or r.public_code = q.external_id
         or r.adopt_question_id = q.id
    );

  create temporary table tmp_affected_attempts on commit drop as
  select distinct a.id
  from public.attempts a
  join public.test_questions tq on tq.test_id = a.test_id
  join tmp_stale_questions s on s.id = tq.question_id;

  select count(*) into v_attempt_deletes from tmp_affected_attempts;
  select count(*) into v_answer_deletes
  from public.attempt_answers aa
  where exists (select 1 from tmp_affected_attempts a where a.id = aa.attempt_id)
     or exists (select 1 from tmp_stale_questions s where s.id = aa.question_id);

  select (
    (select count(*) from public.bookmarks b
      where exists (select 1 from tmp_stale_questions s where s.id = b.question_id))
    + (select count(*) from public.question_progress p
      where exists (select 1 from tmp_stale_questions s where s.id = p.question_id))
    + v_attempt_deletes
    + v_answer_deletes
  )::int into v_dependent_deletes;

  select coalesce(jsonb_agg(jsonb_build_object(
           'row_number', row_no,
           'question_id', public_code
         ) order by row_no), '[]'::jsonb)
    into v_assigned
  from tmp_content_rows
  where public_code is not null;

  if jsonb_array_length(v_errors) > 0 then
    return jsonb_build_object(
      'ok', false, 'applied', false, 'errors', v_errors, 'warnings', v_warnings,
      'question_ids', v_assigned,
      'counts', jsonb_build_object(
        'insert', v_question_inserts, 'update', v_question_updates,
        'delete', v_question_deletes, 'dependent_delete', v_dependent_deletes,
        'attempt_delete', v_attempt_deletes
      )
    );
  end if;

  if not p_apply then
    return jsonb_build_object(
      'ok', true, 'applied', false, 'errors', v_errors, 'warnings', v_warnings,
      'question_ids', v_assigned,
      'counts', jsonb_build_object(
        'insert', v_question_inserts, 'update', v_question_updates,
        'delete', v_question_deletes, 'dependent_delete', v_dependent_deletes,
        'attempt_delete', v_attempt_deletes
      )
    );
  end if;

  for v_rec in
    select distinct on (external_id) *
    from tmp_content_rows
    order by external_id, (chapter_name is not null) desc, row_no
  loop
    select id into v_subject_id
    from public.subjects
    where lower(name) = lower(v_rec.subject_name)
    order by id
    limit 1;

    v_topic_id := null;
    if v_rec.chapter_name is not null then
      select id into v_topic_id from public.topics
      where subject_id = v_subject_id and lower(name) = lower(v_rec.chapter_name)
      order by id limit 1;
      if v_topic_id is null then
        insert into public.topics (subject_id, name, display_order)
        values (
          v_subject_id, v_rec.chapter_name,
          (select coalesce(max(display_order), 0) + 1 from public.topics where subject_id = v_subject_id)
        ) returning id into v_topic_id;
      end if;
    end if;

    v_lesson_id := null;
    if v_rec.topic_name is not null then
      select id into v_lesson_id from public.lessons
      where topic_id = v_topic_id and lower(name) = lower(v_rec.topic_name)
      order by id limit 1;
      if v_lesson_id is null then
        insert into public.lessons (
          topic_id, external_id, name, display_order, required_plan, is_active
        ) values (
          v_topic_id,
          'CSV-L-' || upper(substr(md5(v_subject_id::text || '|' || v_topic_id::text || '|' || lower(v_rec.topic_name)), 1, 24)),
          v_rec.topic_name,
          (select coalesce(max(display_order), 0) + 1 from public.lessons where topic_id = v_topic_id),
          v_rec.required_plan::public.plan_tier,
          v_rec.is_active in ('TRUE', 'YES', '1')
        ) returning id into v_lesson_id;
      end if;
    end if;

    v_question_id := v_rec.adopt_question_id;
    if v_question_id is null then
      select q.id into v_question_id
      from public.questions q
      where q.public_code = v_rec.external_id
         or q.external_id = v_rec.external_id
      order by (q.public_code = v_rec.external_id) desc
      limit 1;
    end if;

    if v_question_id is null then
      insert into public.questions (
        external_id, public_code, topic_id, lesson_id, kind, question_text,
        option_a, option_b, option_c, option_d, correct_option,
        explanation_text, explanation_deep, difficulty, marks, required_plan, is_active,
        content_sync_source
      ) values (
        v_rec.external_id, v_rec.external_id, v_topic_id, v_lesson_id, v_rec.kind::public.question_kind,
        v_rec.question_text, v_rec.option_a, v_rec.option_b, v_rec.option_c,
        v_rec.option_d, v_rec.correct_option, v_rec.explanation_text, v_rec.explanation_deep,
        v_rec.difficulty::public.question_difficulty,
        case when v_rec.marks is null then null else v_rec.marks::numeric end,
        v_rec.required_plan::public.plan_tier,
        v_rec.is_active in ('TRUE', 'YES', '1'), v_source
      )
      returning id into v_question_id;
    else
      update public.questions
      set external_id = v_rec.external_id,
          public_code = v_rec.external_id,
          topic_id = v_topic_id,
          lesson_id = v_lesson_id,
          kind = v_rec.kind::public.question_kind,
          question_text = v_rec.question_text,
          option_a = v_rec.option_a,
          option_b = v_rec.option_b,
          option_c = v_rec.option_c,
          option_d = v_rec.option_d,
          correct_option = v_rec.correct_option,
          explanation_text = v_rec.explanation_text,
          explanation_deep = v_rec.explanation_deep,
          difficulty = v_rec.difficulty::public.question_difficulty,
          marks = case when v_rec.marks is null then null else v_rec.marks::numeric end,
          required_plan = v_rec.required_plan::public.plan_tier,
          is_active = v_rec.is_active in ('TRUE', 'YES', '1'),
          content_sync_source = v_source
      where id = v_question_id;
    end if;

    if v_rec.sample_answer_text is null then
      delete from public.question_sample_answers where question_id = v_question_id;
    else
      insert into public.question_sample_answers (question_id, body, updated_at)
      values (v_question_id, v_rec.sample_answer_text, now())
      on conflict (question_id) do update
        set body = excluded.body, updated_at = now();
    end if;

    delete from public.question_appearances where question_id = v_question_id;
    delete from public.question_textbook_refs where question_id = v_question_id;
    delete from public.question_resources where question_id = v_question_id;
  end loop;

  for v_rec in select * from tmp_content_rows order by row_no
  loop
    select id into v_question_id from public.questions where external_id = v_rec.external_id;
    select id into v_subject_id
    from public.subjects
    where lower(name) = lower(v_rec.subject_name)
    order by id
    limit 1;

    v_paper_external_id := 'CSV-EP-' || upper(substr(md5(
      v_rec.university_id::text || '|' ||
      coalesce(v_rec.college_id::text, '') || '|' ||
      v_subject_id::text || '|' ||
      v_rec.exam_type || '|' ||
      v_rec.exam_year || '|' ||
      v_rec.exam_month::text || '|' ||
      lower(coalesce(v_rec.paper_name, ''))
    ), 1, 24));
    insert into public.exam_papers (
      external_id, university_id, college_id, subject_id,
      exam_year, exam_month, paper_name, exam_type
    ) values (
      v_paper_external_id, v_rec.university_id, v_rec.college_id, v_subject_id,
      v_rec.exam_year::int, v_rec.exam_month::smallint, v_rec.paper_name, v_rec.exam_type
    )
    on conflict (external_id) do update set
      university_id = excluded.university_id,
      college_id = excluded.college_id,
      subject_id = excluded.subject_id,
      exam_year = excluded.exam_year,
      exam_month = excluded.exam_month,
      paper_name = excluded.paper_name,
      exam_type = excluded.exam_type
    returning id into v_paper_id;
    insert into public.question_appearances (question_id, exam_paper_id)
    values (v_question_id, v_paper_id)
    on conflict do nothing;

    if v_rec.textbook_title is not null then
      v_textbook_key := 'CSV-TB-' || upper(substr(md5(
        lower(v_rec.textbook_title) || '|' || lower(coalesce(v_rec.textbook_edition, ''))
      ), 1, 24));
      insert into public.textbooks (sheet_key, title, authors, edition)
      values (v_textbook_key, v_rec.textbook_title, v_rec.textbook_authors, v_rec.textbook_edition)
      on conflict (sheet_key) do update set
        title = excluded.title, authors = excluded.authors, edition = excluded.edition
      returning id into v_textbook_id;
      insert into public.question_textbook_refs (
        question_id, textbook_id, page, section_heading
      ) values (
        v_question_id, v_textbook_id, v_rec.page::int, v_rec.section_heading
      ) on conflict (question_id, textbook_id, page) do update
        set section_heading = excluded.section_heading;
    end if;

    if v_rec.resource_url is not null then
      insert into public.question_resources (
        question_id, title, url, source_label, display_order, is_free
      ) values (
        v_question_id, v_rec.resource_title, v_rec.resource_url,
        v_rec.resource_source_label,
        (select count(*) + 1 from public.question_resources where question_id = v_question_id),
        v_rec.resource_is_free in ('TRUE', 'YES', '1')
      ) on conflict (question_id, url) do update set
        title = excluded.title,
        source_label = excluded.source_label,
        display_order = excluded.display_order,
        is_free = excluded.is_free;
    end if;
  end loop;

  delete from public.attempts a
  using tmp_affected_attempts affected
  where a.id = affected.id;
  delete from public.attempt_answers aa
  using tmp_stale_questions s
  where aa.question_id = s.id;
  delete from public.test_questions tq
  using tmp_stale_questions s
  where tq.question_id = s.id;
  delete from public.questions q
  using tmp_stale_questions s
  where q.id = s.id;

  delete from public.exam_papers ep
  where ep.external_id like 'CSV-EP-%'
    and not exists (
      select 1 from public.question_appearances qa
      where qa.exam_paper_id = ep.id
    );

  perform setval(
    'public.question_public_code_seq',
    greatest(
      v_next_code,
      coalesce((select last_value from public.question_public_code_seq), 1)
    ),
    true
  );

  return jsonb_build_object(
    'ok', true, 'applied', true, 'errors', v_errors, 'warnings', v_warnings,
    'question_ids', v_assigned,
    'counts', jsonb_build_object(
      'insert', v_question_inserts, 'update', v_question_updates,
      'delete', v_question_deletes, 'dependent_delete', v_dependent_deletes,
      'attempt_delete', v_attempt_deletes
    )
  );
end;
$$;

revoke all on function public.sync_content_csv(jsonb, boolean) from public;
revoke all on function public.sync_content_csv(jsonb, boolean) from anon, authenticated;
grant execute on function public.sync_content_csv(jsonb, boolean) to service_role;


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
  if p_match is not null then
    p_match := p_match || jsonb_build_object(
      'question_id',
      coalesce((select q.public_code from public.questions q where q.id = p_question_id), '')
    );
  end if;

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

comment on function public.sync_content_csv(jsonb, boolean) is
  'Validates or applies the question sheet. Identity is the six-digit question_id. The same stem may be more than one question.';


create or replace view public.question_listings
with (security_invoker = false, security_barrier = true) as
select
  q.id,
  q.lesson_id,
  q.topic_id,
  case
    when public.plan_rank(public.current_plan(auth.uid()))
         >= public.plan_rank(q.required_plan)
    then q.question_text
    else null
  end as question_text,
  q.marks,
  q.required_plan,
  q.is_active,
  q.kind,
  q.difficulty,
  q.has_direct_answer,
  q.has_explanation,
  q.public_code
from public.questions q
where q.is_active;

comment on view public.question_listings is
  'Active question cards. question_text is null when current_plan() is below required_plan. public_code is the six-digit sheet id. No explanation, options, or answer key.';

revoke all on table public.question_listings from public, anon;
grant select on table public.question_listings to authenticated, service_role;

drop view if exists public.pyq_teasers;

create view public.pyq_teasers
with (security_invoker = true) as
select
  q.id,
  q.lesson_id,
  q.topic_id,
  q.question_text,
  q.marks,
  q.required_plan,
  q.is_active,
  (
    select count(*)::int
    from public.question_appearances a
    where a.question_id = q.id
  ) as appearance_count,
  q.kind,
  q.difficulty,
  q.has_direct_answer,
  q.has_explanation,
  q.public_code
from public.questions q
where q.is_active;

comment on view public.pyq_teasers is
  'Theory + MCQ stems + frequency + difficulty + content flags + six-digit id. '
  'No sample-answer text, no explanation text, no MCQ keys.';

grant select on public.pyq_teasers to authenticated, service_role;
