-- Question-sheet columns (docs/02_DATABASE_SCHEMA.md §9.2c).
-- A data-entry row is one question on one sitting:
--   university (alias + name) + optional college + exam type + year + month
--   + optional paper label + subject + optional chapter/topic + stem.
-- Course is ignored. State, when filled, must match universities.state.

-- ---------------------------------------------------------------------------
-- Sheet token helpers (service role / sync only)
-- ---------------------------------------------------------------------------

create or replace function public.normalize_sheet_exam_type(p_raw text)
returns text
language plpgsql
immutable
as $$
declare
  v text;
begin
  -- Lower first. In this database [a-z] does not match uppercase, so stripping
  -- non-letters before lower() would delete "PROF" entirely.
  -- "PRE PROF", "Pre-Prof", and the sheet spelling "Pre Proff" collapse together.
  v := regexp_replace(lower(btrim(coalesce(p_raw, ''))), '[^a-z]+', '', 'g');
  return case v
    when 'prof' then 'prof'
    when 'supply' then 'supply'
    when 'preprof' then 'pre_prof'
    when 'preproff' then 'pre_prof'
    when 'internal' then 'internal'
    else null
  end;
end;
$$;

create or replace function public.normalize_sheet_exam_month(p_raw text)
returns smallint
language plpgsql
immutable
as $$
declare
  v text;
  n int;
begin
  v := lower(btrim(coalesce(p_raw, '')));
  if v = '' then
    return null;
  end if;
  if v ~ '^[0-9]+(\.0+)?$' then
    n := split_part(v, '.', 1)::int;
    if n between 1 and 12 then
      return n::smallint;
    end if;
    return null;
  end if;
  v := regexp_replace(split_part(v, ' ', 1), '[^a-z]', '', 'g');
  return case v
    when 'january' then 1 when 'jan' then 1
    when 'february' then 2 when 'feb' then 2
    when 'march' then 3 when 'mar' then 3
    when 'april' then 4 when 'apr' then 4
    when 'may' then 5
    when 'june' then 6 when 'jun' then 6
    when 'july' then 7 when 'jul' then 7
    when 'august' then 8 when 'aug' then 8
    when 'september' then 9 when 'sep' then 9 when 'sept' then 9
    when 'october' then 10 when 'oct' then 10
    when 'november' then 11 when 'nov' then 11
    when 'december' then 12 when 'dec' then 12
    else null
  end;
end;
$$;

revoke all on function public.normalize_sheet_exam_type(text) from public, anon, authenticated;
revoke all on function public.normalize_sheet_exam_month(text) from public, anon, authenticated;
grant execute on function public.normalize_sheet_exam_type(text) to service_role;
grant execute on function public.normalize_sheet_exam_month(text) to service_role;

-- ---------------------------------------------------------------------------
-- exam_papers: campus, month, four exam types, optional paper label
-- ---------------------------------------------------------------------------

alter table public.exam_papers
  add column if not exists college_id uuid references public.colleges(id) on delete set null;

alter table public.exam_papers
  add column if not exists exam_month smallint;

alter table public.exam_papers
  drop constraint if exists exam_papers_exam_month_check;

alter table public.exam_papers
  add constraint exam_papers_exam_month_check
  check (exam_month is null or exam_month between 1 and 12);

do $$
declare
  r record;
begin
  for r in
    select con.conname
    from pg_constraint con
    join pg_class rel on rel.oid = con.conrelid
    join pg_namespace nsp on nsp.oid = rel.relnamespace
    where nsp.nspname = 'public'
      and rel.relname = 'exam_papers'
      and con.contype = 'c'
      and pg_get_constraintdef(con.oid) ilike '%exam_type%'
  loop
    execute format('alter table public.exam_papers drop constraint %I', r.conname);
  end loop;
end $$;

-- Older rows used exam_type 'university' for the professional paper.
update public.exam_papers
set exam_type = 'prof'
where exam_type = 'university';

alter table public.exam_papers
  alter column exam_type set default 'prof';

alter table public.exam_papers
  add constraint exam_papers_exam_type_check
  check (exam_type in ('prof', 'supply', 'pre_prof', 'internal'));

alter table public.exam_papers
  alter column paper_name drop not null;

create index if not exists idx_exam_papers_college
  on public.exam_papers (college_id)
  where college_id is not null;

create index if not exists idx_exam_papers_sitting
  on public.exam_papers (university_id, subject_id, exam_year, exam_month);

comment on column public.exam_papers.exam_type is
  'prof | supply | pre_prof | internal. Sheet spellings PRE PROF and Pre Proff map to pre_prof.';

comment on column public.exam_papers.exam_month is
  'Sitting month, 1–12. Null only on papers imported before the question sheet required a month.';

comment on column public.exam_papers.college_id is
  'Optional campus. Blank is allowed for every exam type, including pre_prof and internal. When the sheet fills college_alias and college_name, both must match one colleges row of this university.';

comment on column public.exam_papers.paper_name is
  'Printed paper label (Paper I, Paper II). Null when the sheet leaves paper_number blank.';

-- ---------------------------------------------------------------------------
-- questions: short explanation (exp_1) stays explanation_text; exp_2 is deeper
-- ---------------------------------------------------------------------------

alter table public.questions
  add column if not exists explanation_deep text;

comment on column public.questions.explanation_text is
  'Sheet exp_1. Short explanation. Same plan gate as the question row.';

comment on column public.questions.explanation_deep is
  'Sheet exp_2. Longer explanation. Same plan gate as the question row.';

-- ---------------------------------------------------------------------------
-- Importer
-- ---------------------------------------------------------------------------

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
  v_allowed_columns text[] := array[
    '_row_number', 'course', 'state',
    'university_alias', 'university_name',
    'college_alias', 'college_name',
    'exam_type', 'year', 'month', 'paper_number',
    'subject_name', 'chapter_name', 'topic_name',
    'question_type', 'marks', 'question_text',
    'option_a', 'option_b', 'option_c', 'option_d', 'correct_option',
    'answers', 'exp_1', 'exp_2',
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
  create temporary table tmp_content_rows (
    row_no int not null,
    external_id text not null,
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

    v_external_id := 'CSV-' || upper(substr(md5(
      lower(regexp_replace(v_subject, '\s+', ' ', 'g')) || '|' ||
      coalesce(v_kind, '') || '|' ||
      lower(regexp_replace(v_stem, '\s+', ' ', 'g'))
    ), 1, 24));

    insert into tmp_content_rows (
      row_no, external_id, subject_name, question_text, kind,
      option_a, option_b, option_c, option_d, correct_option,
      chapter_name, topic_name, marks,
      university_id, college_id, exam_year, exam_month, paper_name, exam_type,
      textbook_title, textbook_authors, textbook_edition, page, section_heading,
      explanation_text, explanation_deep, sample_answer_text,
      difficulty, required_plan, is_active,
      resource_title, resource_url, resource_source_label, resource_is_free
    ) values (
      v_row_no, v_external_id, coalesce(nullif(v_subject, ''), '(missing)'), coalesce(nullif(v_stem, ''), '(missing)'),
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

  -- Repeated rows intentionally add appearances, but their question body must agree.
  for v_rec in
    select external_id, min(row_no) as first_row
    from tmp_content_rows
    group by external_id
    having count(distinct concat_ws('|', coalesce(option_a, ''), coalesce(option_b, ''),
      coalesce(option_c, ''), coalesce(option_d, ''), coalesce(correct_option, ''),
      coalesce(chapter_name, ''), coalesce(topic_name, ''), coalesce(marks, ''),
      coalesce(explanation_text, ''), coalesce(explanation_deep, ''),
      coalesce(sample_answer_text, ''))) > 1
  loop
    v_errors := v_errors || jsonb_build_array(
      'Questions row ' || v_rec.first_row || ': repeated subject/question_type/stem rows must use identical chapter, topic, marks, options, answers, and explanations'
    );
  end loop;

  for v_rec in
    select r.external_id, min(r.row_no) as first_row
    from tmp_content_rows r
    join public.questions q on q.external_id = r.external_id
    where q.content_sync_source is distinct from v_source
    group by r.external_id
  loop
    v_errors := v_errors || jsonb_build_array(
      'Questions row ' || v_rec.first_row || ': generated identity conflicts with non-CSV content'
    );
  end loop;

  select count(*) filter (where q.id is null),
         count(*) filter (where q.id is not null)
    into v_question_inserts, v_question_updates
  from (select distinct external_id from tmp_content_rows) r
  left join public.questions q on q.external_id = r.external_id;

  select count(*) into v_question_deletes
  from public.questions q
  where q.content_sync_source = v_source
    and not exists (
      select 1 from tmp_content_rows r where r.external_id = q.external_id
    );

  create temporary table tmp_stale_questions on commit drop as
  select q.id
  from public.questions q
  where q.content_sync_source = v_source
    and not exists (
      select 1 from tmp_content_rows r where r.external_id = q.external_id
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

  if jsonb_array_length(v_errors) > 0 then
    return jsonb_build_object(
      'ok', false, 'applied', false, 'errors', v_errors, 'warnings', v_warnings,
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

    insert into public.questions (
      external_id, topic_id, lesson_id, kind, question_text,
      option_a, option_b, option_c, option_d, correct_option,
      explanation_text, explanation_deep, difficulty, marks, required_plan, is_active,
      content_sync_source
    ) values (
      v_rec.external_id, v_topic_id, v_lesson_id, v_rec.kind::public.question_kind,
      v_rec.question_text, v_rec.option_a, v_rec.option_b, v_rec.option_c,
      v_rec.option_d, v_rec.correct_option, v_rec.explanation_text, v_rec.explanation_deep,
      v_rec.difficulty::public.question_difficulty,
      case when v_rec.marks is null then null else v_rec.marks::numeric end,
      v_rec.required_plan::public.plan_tier,
      v_rec.is_active in ('TRUE', 'YES', '1'), v_source
    )
    on conflict (external_id) do update set
      topic_id = excluded.topic_id,
      lesson_id = excluded.lesson_id,
      kind = excluded.kind,
      question_text = excluded.question_text,
      option_a = excluded.option_a,
      option_b = excluded.option_b,
      option_c = excluded.option_c,
      option_d = excluded.option_d,
      correct_option = excluded.correct_option,
      explanation_text = excluded.explanation_text,
      explanation_deep = excluded.explanation_deep,
      difficulty = excluded.difficulty,
      marks = excluded.marks,
      required_plan = excluded.required_plan,
      is_active = excluded.is_active,
      content_sync_source = excluded.content_sync_source
    returning id into v_question_id;

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

  return jsonb_build_object(
    'ok', true, 'applied', true, 'errors', v_errors, 'warnings', v_warnings,
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

comment on function public.sync_content_csv(jsonb, boolean) is
  'Validates or applies the question sheet. University alias and name must already match one universities row; subject must already exist; chapter and topic are free-text tags.';
