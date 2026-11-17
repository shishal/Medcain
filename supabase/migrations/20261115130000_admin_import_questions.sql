-- Bulk question import for the website admin.
-- Accepts the old Questions sheet (one row is one paper on a question).
-- Rows that share a subject, question type, and question text are one question.
-- A filled question_id updates that question. A blank question_id updates the
-- question with the same text when there is exactly one, and otherwise creates.
-- Questions that are not in the file are left alone. sync_content_csv stays retired.

create or replace function public.admin_import_questions(
  p_rows jsonb,
  p_defaults jsonb,
  p_apply boolean default false
) returns jsonb
language plpgsql
security definer
set search_path = pg_temp, public
as $$
declare
  v_errors jsonb := '[]'::jsonb;
  v_row jsonb;
  v_key text;
  v_row_no int := 1;
  v_content int := 0;
  v_blank boolean;
  v_allowed text[] := array[
    '_row_number', 'course', 'state',
    'university_alias', 'university_name',
    'college_alias', 'college_name',
    'exam_type', 'year', 'month', 'paper_number',
    'subject_name', 'chapter_name', 'topic_name',
    'question_type', 'marks', 'question_text',
    'option_a', 'option_b', 'option_c', 'option_d', 'correct_option',
    'question_id', 'public_code', 'answers', 'exp_1', 'exp_2',
    'textbook_title', 'textbook_authors', 'textbook_edition',
    'page', 'section_heading', 'difficulty', 'required_plan', 'is_active',
    'resource_title', 'resource_url', 'resource_source_label', 'resource_is_free'
  ];
  v_def_subject uuid;
  v_def_subject_name text;
  v_def_university uuid;
  v_def_college uuid;
  v_def_year text;
  v_def_month text;
  v_def_exam text;
  v_def_paper text;
  v_def_difficulty text;
  v_def_plan text;
  v_def_active text;
  v_subject text;
  v_subject_id uuid;
  v_stem text;
  v_kind text;
  v_alias text;
  v_uni_name text;
  v_sheet_uni_name text;
  v_state text;
  v_uni_state text;
  v_university_id uuid;
  v_college_alias text;
  v_college_name text;
  v_college_id uuid;
  v_year text;
  v_year_int int;
  v_month_raw text;
  v_month smallint;
  v_exam_raw text;
  v_exam text;
  v_paper text;
  v_chapter text;
  v_topic text;
  v_marks text;
  v_code text;
  v_code_raw text;
  v_code_other text;
  v_qid_bad boolean;
  v_difficulty text;
  v_plan text;
  v_active_raw text;
  v_active boolean;
  v_free_raw text;
  v_free boolean;
  v_tb_title text;
  v_page text;
  v_res_title text;
  v_res_url text;
  v_legacy text;
  v_fp text;
  v_opt_a text;
  v_opt_b text;
  v_opt_c text;
  v_opt_d text;
  v_correct text;
  v_exp_1 text;
  v_exp_2 text;
  v_answer text;
  v_bad boolean;
  v_grp record;
  v_match_count int;
  v_existing uuid;
  v_existing_code text;
  v_other_code text;
  v_old_subject uuid;
  v_creates int := 0;
  v_updates int := 0;
  v_applied boolean := false;
  v_questions jsonb := '[]'::jsonb;
  v_codes jsonb := '[]'::jsonb;
  v_saved jsonb;
  v_question_id uuid;
  v_seen text[];
  v_sit_key text;
  v_sittings jsonb;
  v_body jsonb;
  v_first record;
  v_sitting record;
begin
  perform public.assert_admin();
  p_apply := coalesce(p_apply, false);

  if p_defaults is null or jsonb_typeof(p_defaults) = 'null' then
    p_defaults := '{}'::jsonb;
  elsif jsonb_typeof(p_defaults) <> 'object' then
    return jsonb_build_object(
      'ok', false,
      'applied', false,
      'errors', jsonb_build_array('Paper defaults must be an object.'),
      'creates', 0,
      'updates', 0,
      'row_count', 0,
      'questions', '[]'::jsonb,
      'codes', '[]'::jsonb
    );
  end if;

  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    return jsonb_build_object(
      'ok', false,
      'applied', false,
      'errors', jsonb_build_array('Input must be a JSON array of spreadsheet rows.'),
      'creates', 0,
      'updates', 0,
      'row_count', 0,
      'questions', '[]'::jsonb,
      'codes', '[]'::jsonb
    );
  end if;

  if jsonb_array_length(p_rows) > 2000 then
    return jsonb_build_object(
      'ok', false,
      'applied', false,
      'errors', jsonb_build_array('A file can hold 300 questions. Split this one.'),
      'creates', 0,
      'updates', 0,
      'row_count', 0,
      'questions', '[]'::jsonb,
      'codes', '[]'::jsonb
    );
  end if;

  begin
    v_def_subject := nullif(btrim(coalesce(p_defaults->>'subject_id', '')), '')::uuid;
  exception
    when invalid_text_representation then
      v_def_subject := null;
      v_errors := v_errors || jsonb_build_array('Paper defaults: choose a subject that already exists.');
  end;
  if v_def_subject is not null then
    select s.name into v_def_subject_name
    from public.subjects s
    where s.id = v_def_subject;
    if v_def_subject_name is null then
      v_errors := v_errors || jsonb_build_array('Paper defaults: choose a subject that already exists.');
      v_def_subject := null;
    end if;
  end if;

  begin
    v_def_university := nullif(btrim(coalesce(p_defaults->>'university_id', '')), '')::uuid;
  exception
    when invalid_text_representation then
      v_def_university := null;
      v_errors := v_errors || jsonb_build_array('Paper defaults: choose a university that already exists.');
  end;
  if v_def_university is not null and not exists (
    select 1 from public.universities u where u.id = v_def_university
  ) then
    v_errors := v_errors || jsonb_build_array('Paper defaults: choose a university that already exists.');
    v_def_university := null;
  end if;

  begin
    v_def_college := nullif(btrim(coalesce(p_defaults->>'college_id', '')), '')::uuid;
  exception
    when invalid_text_representation then
      v_def_college := null;
      v_errors := v_errors || jsonb_build_array('Paper defaults: that college is not in this university.');
  end;
  if v_def_college is not null then
    if v_def_university is null or not exists (
      select 1
      from public.colleges c
      where c.id = v_def_college
        and c.university_id = v_def_university
    ) then
      v_errors := v_errors || jsonb_build_array('Paper defaults: that college is not in this university.');
      v_def_college := null;
    end if;
  end if;

  v_def_year := btrim(coalesce(p_defaults->>'year', ''));
  if v_def_year ~ '^[0-9]+(\.0+)?$' then
    v_def_year := split_part(v_def_year, '.', 1);
  end if;
  if v_def_year <> '' and v_def_year !~ '^[0-9]{4}$' then
    v_errors := v_errors || jsonb_build_array('Paper defaults: year must be from 1990 to 2100.');
    v_def_year := '';
  elsif v_def_year <> '' and (v_def_year::int < 1990 or v_def_year::int > 2100) then
    v_errors := v_errors || jsonb_build_array('Paper defaults: year must be from 1990 to 2100.');
    v_def_year := '';
  end if;

  v_def_month := btrim(coalesce(p_defaults->>'month', ''));
  if v_def_month <> '' and public.normalize_sheet_exam_month(v_def_month) is null then
    v_errors := v_errors || jsonb_build_array('Paper defaults: month must be a month name or 1–12.');
    v_def_month := '';
  end if;

  v_def_exam := btrim(coalesce(p_defaults->>'exam_type', ''));
  if v_def_exam <> '' and public.normalize_sheet_exam_type(v_def_exam) is null then
    v_errors := v_errors || jsonb_build_array('Paper defaults: exam type must be PROF, SUPPLY, PRE PROF, or INTERNAL.');
    v_def_exam := '';
  end if;

  v_def_paper := nullif(btrim(coalesce(p_defaults->>'paper_number', '')), '');
  v_def_difficulty := lower(btrim(coalesce(p_defaults->>'difficulty', '')));
  if v_def_difficulty <> '' and v_def_difficulty not in ('must', 'should', 'could') then
    v_errors := v_errors || jsonb_build_array('Paper defaults: difficulty must be must, should, or could.');
    v_def_difficulty := '';
  end if;
  v_def_plan := lower(btrim(coalesce(p_defaults->>'required_plan', '')));
  if v_def_plan <> '' and v_def_plan not in ('free', 'pro', 'elite') then
    v_errors := v_errors || jsonb_build_array('Paper defaults: required plan must be free, pro, or elite.');
    v_def_plan := '';
  end if;
  v_def_active := upper(btrim(coalesce(p_defaults->>'is_active', '')));
  if v_def_active <> '' and v_def_active not in ('TRUE', 'FALSE', 'YES', 'NO', '1', '0') then
    v_errors := v_errors || jsonb_build_array('Paper defaults: visible must be true or false.');
    v_def_active := '';
  end if;

  for v_row in select value from jsonb_array_elements(p_rows)
  loop
    if jsonb_typeof(v_row) = 'object' then
      v_blank := true;
      for v_key in select jsonb_object_keys(v_row)
      loop
        if v_key <> '_row_number' and btrim(coalesce(v_row->>v_key, '')) <> '' then
          v_blank := false;
        end if;
      end loop;
      if not v_blank then
        v_content := v_content + 1;
      end if;
    else
      v_content := v_content + 1;
    end if;
  end loop;

  if v_content = 0 then
    return jsonb_build_object(
      'ok', false,
      'applied', false,
      'errors', v_errors || jsonb_build_array('The file has no questions.'),
      'creates', 0,
      'updates', 0,
      'row_count', 0,
      'questions', '[]'::jsonb,
      'codes', '[]'::jsonb
    );
  end if;
  if v_content > 300 then
    return jsonb_build_object(
      'ok', false,
      'applied', false,
      'errors', v_errors || jsonb_build_array('A file can hold 300 questions. Split this one.'),
      'creates', 0,
      'updates', 0,
      'row_count', v_content,
      'questions', '[]'::jsonb,
      'codes', '[]'::jsonb
    );
  end if;

  drop table if exists pg_temp.tmp_import_rows;
  drop table if exists pg_temp.tmp_import_groups;
  drop table if exists pg_temp.tmp_import_existing;
  create temporary table tmp_import_rows (
    row_no int not null,
    legacy_id text not null,
    subject_id uuid,
    subject_name text,
    question_text text,
    kind text,
    public_code text,
    body_fp text,
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
    exam_year int,
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
    is_active boolean,
    resource_title text,
    resource_url text,
    resource_source_label text,
    resource_is_free boolean
  ) on commit drop;
  create temporary table tmp_import_groups (
    legacy_id text primary key,
    first_row int not null,
    existing_id uuid,
    action text not null,
    code text,
    paper_count int not null,
    stem text not null,
    subject_id uuid
  ) on commit drop;

  for v_row in select value from jsonb_array_elements(p_rows)
  loop
    v_row_no := v_row_no + 1;
    if jsonb_typeof(v_row) <> 'object' then
      v_errors := v_errors || jsonb_build_array(
        'Questions row ' || v_row_no || ': each row must be a spreadsheet row.'
      );
      continue;
    end if;
    if coalesce(v_row->>'_row_number', '') ~ '^[0-9]+$' then
      v_row_no := (v_row->>'_row_number')::int;
    end if;

    v_blank := true;
    for v_key in select jsonb_object_keys(v_row)
    loop
      if v_key <> '_row_number' and btrim(coalesce(v_row->>v_key, '')) <> '' then
        v_blank := false;
      end if;
      if not (v_key = any(v_allowed)) then
        v_errors := v_errors || jsonb_build_array(
          'Questions row ' || v_row_no || ': unsupported column "' || v_key ||
          '". Use the Questions sheet columns.'
        );
      end if;
    end loop;
    if v_blank then
      continue;
    end if;

    v_subject := btrim(coalesce(v_row->>'subject_name', ''));
    v_stem := btrim(coalesce(v_row->>'question_text', ''));
    v_kind := lower(btrim(coalesce(v_row->>'question_type', '')));
    v_subject_id := null;
    v_university_id := null;
    v_college_id := null;
    v_year_int := null;
    v_month := null;
    v_exam := null;

    if v_subject = '' then
      if v_def_subject is null then
        v_errors := v_errors || jsonb_build_array('Questions row ' || v_row_no || ': subject_name is required');
      else
        v_subject_id := v_def_subject;
        v_subject := v_def_subject_name;
      end if;
    else
      select s.id, s.name
        into v_subject_id, v_uni_name
      from public.subjects s
      where lower(s.name) = lower(v_subject)
      order by s.id
      limit 1;
      if v_subject_id is null then
        v_errors := v_errors || jsonb_build_array(
          'Questions row ' || v_row_no || ': subject_name "' || v_subject || '" is not in subjects'
        );
      else
        v_subject := v_uni_name;
      end if;
    end if;

    if v_stem = '' then
      v_errors := v_errors || jsonb_build_array('Questions row ' || v_row_no || ': question_text is required');
    end if;
    if v_kind = '' then
      v_errors := v_errors || jsonb_build_array('Questions row ' || v_row_no || ': question_type is required');
    elsif v_kind not in ('mcq', 'pyq_theory') then
      v_errors := v_errors || jsonb_build_array(
        'Questions row ' || v_row_no || ': question_type must be pyq_theory or mcq'
      );
    end if;

    v_opt_a := nullif(btrim(coalesce(v_row->>'option_a', '')), '');
    v_opt_b := nullif(btrim(coalesce(v_row->>'option_b', '')), '');
    v_opt_c := nullif(btrim(coalesce(v_row->>'option_c', '')), '');
    v_opt_d := nullif(btrim(coalesce(v_row->>'option_d', '')), '');
    v_correct := nullif(upper(btrim(coalesce(v_row->>'correct_option', ''))), '');
    if v_kind = 'mcq' then
      if v_opt_a is null then
        v_errors := v_errors || jsonb_build_array('Questions row ' || v_row_no || ': option_a is required for mcq');
      end if;
      if v_opt_b is null then
        v_errors := v_errors || jsonb_build_array('Questions row ' || v_row_no || ': option_b is required for mcq');
      end if;
      if v_opt_c is null then
        v_errors := v_errors || jsonb_build_array('Questions row ' || v_row_no || ': option_c is required for mcq');
      end if;
      if v_opt_d is null then
        v_errors := v_errors || jsonb_build_array('Questions row ' || v_row_no || ': option_d is required for mcq');
      end if;
      if v_correct is null or v_correct not in ('A', 'B', 'C', 'D') then
        v_errors := v_errors || jsonb_build_array(
          'Questions row ' || v_row_no || ': correct_option must be A, B, C, or D'
        );
      end if;
    elsif v_kind = 'pyq_theory' and concat_ws('',
      coalesce(v_opt_a, ''), coalesce(v_opt_b, ''), coalesce(v_opt_c, ''),
      coalesce(v_opt_d, ''), coalesce(v_correct, '')
    ) <> '' then
      v_errors := v_errors || jsonb_build_array(
        'Questions row ' || v_row_no || ': pyq_theory rows must leave option and correct_option cells blank'
      );
    end if;

    v_chapter := btrim(coalesce(v_row->>'chapter_name', ''));
    v_topic := btrim(coalesce(v_row->>'topic_name', ''));
    if v_topic <> '' and v_chapter = '' then
      v_errors := v_errors || jsonb_build_array(
        'Questions row ' || v_row_no || ': topic_name requires chapter_name'
      );
    end if;

    v_alias := btrim(coalesce(v_row->>'university_alias', ''));
    v_sheet_uni_name := btrim(coalesce(v_row->>'university_name', ''));
    v_state := btrim(coalesce(v_row->>'state', ''));
    if v_alias <> '' then
      select u.id, u.name, u.state
        into v_university_id, v_uni_name, v_uni_state
      from public.universities u
      where lower(u.code) = lower(v_alias)
      order by u.id
      limit 1;
      if v_sheet_uni_name = '' then
        v_errors := v_errors || jsonb_build_array(
          'Questions row ' || v_row_no || ': university_name is required'
        );
        v_university_id := null;
      elsif v_university_id is null then
        v_errors := v_errors || jsonb_build_array(
          'Questions row ' || v_row_no || ': university_alias "' || v_alias || '" does not exist'
        );
      elsif lower(regexp_replace(v_uni_name, '\s+', ' ', 'g'))
            is distinct from lower(regexp_replace(v_sheet_uni_name, '\s+', ' ', 'g')) then
        v_errors := v_errors || jsonb_build_array(
          'Questions row ' || v_row_no || ': university_name does not match university_alias "' || v_alias || '"'
        );
        v_university_id := null;
      elsif v_state <> '' and lower(regexp_replace(coalesce(v_uni_state, ''), '\s+', ' ', 'g'))
            is distinct from lower(regexp_replace(v_state, '\s+', ' ', 'g')) then
        v_errors := v_errors || jsonb_build_array(
          'Questions row ' || v_row_no || ': state does not match the university'
        );
      end if;
    elsif v_sheet_uni_name <> '' then
      v_errors := v_errors || jsonb_build_array(
        'Questions row ' || v_row_no || ': university_alias is required'
      );
    elsif v_def_university is null then
      v_errors := v_errors || jsonb_build_array(
        'Questions row ' || v_row_no || ': university_alias is required'
      );
    else
      select u.state into v_uni_state
      from public.universities u
      where u.id = v_def_university;
      v_university_id := v_def_university;
      if v_state <> '' and lower(regexp_replace(coalesce(v_uni_state, ''), '\s+', ' ', 'g'))
            is distinct from lower(regexp_replace(v_state, '\s+', ' ', 'g')) then
        v_errors := v_errors || jsonb_build_array(
          'Questions row ' || v_row_no || ': state does not match the university'
        );
      end if;
    end if;

    v_college_alias := btrim(coalesce(v_row->>'college_alias', ''));
    v_college_name := btrim(coalesce(v_row->>'college_name', ''));
    if (v_college_alias = '') <> (v_college_name = '') then
      v_errors := v_errors || jsonb_build_array(
        'Questions row ' || v_row_no || ': college_alias and college_name must be filled together'
      );
    elsif v_college_alias <> '' then
      if v_university_id is null then
        v_college_id := null;
      else
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
    elsif v_def_college is not null and v_university_id is not distinct from v_def_university then
      v_college_id := v_def_college;
    end if;

    v_year := btrim(coalesce(v_row->>'year', ''));
    if v_year = '' then
      v_year := v_def_year;
    end if;
    if v_year ~ '^[0-9]+(\.0+)?$' then
      v_year := split_part(v_year, '.', 1);
    end if;
    if v_year = '' then
      v_errors := v_errors || jsonb_build_array('Questions row ' || v_row_no || ': year is required');
    elsif v_year !~ '^[0-9]{4}$' then
      v_errors := v_errors || jsonb_build_array(
        'Questions row ' || v_row_no || ': year must be from 1990 to 2100'
      );
    elsif v_year::int < 1990 or v_year::int > 2100 then
      v_errors := v_errors || jsonb_build_array(
        'Questions row ' || v_row_no || ': year must be from 1990 to 2100'
      );
    else
      v_year_int := v_year::int;
    end if;

    v_month_raw := btrim(coalesce(v_row->>'month', ''));
    if v_month_raw = '' then
      v_month_raw := v_def_month;
    end if;
    if v_month_raw = '' then
      v_errors := v_errors || jsonb_build_array('Questions row ' || v_row_no || ': month is required');
    else
      v_month := public.normalize_sheet_exam_month(v_month_raw);
      if v_month is null then
        v_errors := v_errors || jsonb_build_array(
          'Questions row ' || v_row_no || ': month must be a month name such as May or June'
        );
      end if;
    end if;

    v_exam_raw := btrim(coalesce(v_row->>'exam_type', ''));
    if v_exam_raw = '' then
      v_exam_raw := v_def_exam;
    end if;
    if v_exam_raw = '' then
      v_errors := v_errors || jsonb_build_array('Questions row ' || v_row_no || ': exam_type is required');
    else
      v_exam := public.normalize_sheet_exam_type(v_exam_raw);
      if v_exam is null then
        v_errors := v_errors || jsonb_build_array(
          'Questions row ' || v_row_no || ': exam_type must be PROF, SUPPLY, PRE PROF, or INTERNAL'
        );
      end if;
    end if;

    v_paper := btrim(coalesce(v_row->>'paper_number', ''));
    if v_paper = '' then
      v_paper := coalesce(v_def_paper, '');
    end if;

    v_marks := btrim(coalesce(v_row->>'marks', ''));
    if v_marks ~ '^[0-9]+(\.0+)?$' then
      v_marks := split_part(v_marks, '.', 1);
    end if;
    if v_marks <> '' and v_marks !~ '^[0-9]+([.][0-9]+)?$' then
      v_errors := v_errors || jsonb_build_array(
        'Questions row ' || v_row_no || ': marks must be a positive number'
      );
      v_marks := '';
    elsif v_marks <> '' and v_marks::numeric <= 0 then
      v_errors := v_errors || jsonb_build_array(
        'Questions row ' || v_row_no || ': marks must be greater than zero'
      );
      v_marks := '';
    end if;

    v_tb_title := btrim(coalesce(v_row->>'textbook_title', ''));
    v_page := btrim(coalesce(v_row->>'page', ''));
    if (v_tb_title = '') <> (v_page = '') then
      v_errors := v_errors || jsonb_build_array(
        'Questions row ' || v_row_no || ': textbook_title and page must be filled together'
      );
    end if;
    if v_page <> '' and v_page !~ '^[0-9]+$' then
      v_errors := v_errors || jsonb_build_array(
        'Questions row ' || v_row_no || ': page must be a positive integer'
      );
    elsif v_page <> '' and v_page::int <= 0 then
      v_errors := v_errors || jsonb_build_array(
        'Questions row ' || v_row_no || ': page must be greater than zero'
      );
    end if;

    v_res_title := btrim(coalesce(v_row->>'resource_title', ''));
    v_res_url := btrim(coalesce(v_row->>'resource_url', ''));
    if (v_res_title = '') <> (v_res_url = '') then
      v_errors := v_errors || jsonb_build_array(
        'Questions row ' || v_row_no || ': resource_title and resource_url must be filled together'
      );
    end if;
    if v_res_url <> '' and v_res_url !~ '^https://' then
      v_errors := v_errors || jsonb_build_array(
        'Questions row ' || v_row_no || ': resource_url must start with https://'
      );
    end if;

    v_difficulty := lower(btrim(coalesce(v_row->>'difficulty', '')));
    if v_difficulty = '' then
      v_difficulty := v_def_difficulty;
    end if;
    if v_difficulty = '' then
      v_difficulty := 'should';
    elsif v_difficulty not in ('must', 'should', 'could') then
      v_errors := v_errors || jsonb_build_array(
        'Questions row ' || v_row_no || ': difficulty must be must, should, or could (blank = should)'
      );
      v_difficulty := 'should';
    end if;

    v_plan := lower(btrim(coalesce(v_row->>'required_plan', '')));
    if v_plan = '' then
      v_plan := v_def_plan;
    end if;
    if v_plan = '' then
      v_plan := 'free';
    elsif v_plan not in ('free', 'pro', 'elite') then
      v_errors := v_errors || jsonb_build_array(
        'Questions row ' || v_row_no || ': required_plan must be free, pro, or elite'
      );
      v_plan := 'free';
    end if;

    v_active_raw := upper(btrim(coalesce(v_row->>'is_active', '')));
    if v_active_raw = '' then
      v_active_raw := v_def_active;
    end if;
    if v_active_raw = '' then
      v_active_raw := 'TRUE';
    end if;
    if v_active_raw not in ('TRUE', 'FALSE', 'YES', 'NO', '1', '0') then
      v_errors := v_errors || jsonb_build_array(
        'Questions row ' || v_row_no || ': is_active must be TRUE or FALSE'
      );
      v_active := true;
    else
      v_active := v_active_raw in ('TRUE', 'YES', '1');
    end if;

    v_free_raw := upper(btrim(coalesce(v_row->>'resource_is_free', '')));
    if v_free_raw = '' then
      v_free_raw := 'TRUE';
    end if;
    if v_free_raw not in ('TRUE', 'FALSE', 'YES', 'NO', '1', '0') then
      v_errors := v_errors || jsonb_build_array(
        'Questions row ' || v_row_no || ': resource_is_free must be TRUE or FALSE'
      );
      v_free := true;
    else
      v_free := v_free_raw in ('TRUE', 'YES', '1');
    end if;

    v_code := null;
    v_code_other := null;
    v_qid_bad := false;
    v_code_raw := btrim(coalesce(v_row->>'question_id', ''));
    if v_code_raw ~ '^[0-9]+(\.0+)?$' then
      v_code_raw := split_part(v_code_raw, '.', 1);
    end if;
    if v_code_raw <> '' and v_code_raw !~ '^[0-9]{1,6}$' then
      v_qid_bad := true;
      v_errors := v_errors || jsonb_build_array(
        'Questions row ' || v_row_no || ': question_id must be a number from 1 to 999999'
      );
    elsif v_code_raw <> '' and v_code_raw::int = 0 then
      v_qid_bad := true;
      v_errors := v_errors || jsonb_build_array(
        'Questions row ' || v_row_no || ': question_id must be a number from 1 to 999999'
      );
    elsif v_code_raw <> '' then
      v_code := lpad(v_code_raw, 6, '0');
    end if;
    v_code_raw := btrim(coalesce(v_row->>'public_code', ''));
    if v_code_raw ~ '^[0-9]+(\.0+)?$' then
      v_code_raw := split_part(v_code_raw, '.', 1);
    end if;
    if v_code_raw <> '' and v_code_raw !~ '^[0-9]{1,6}$' then
      v_errors := v_errors || jsonb_build_array(
        'Questions row ' || v_row_no || ': public_code must be a number from 1 to 999999'
      );
    elsif v_code_raw <> '' and v_code_raw::int = 0 then
      v_errors := v_errors || jsonb_build_array(
        'Questions row ' || v_row_no || ': public_code must be a number from 1 to 999999'
      );
    elsif v_code_raw <> '' then
      v_code_other := lpad(v_code_raw, 6, '0');
    end if;
    if v_code is not null and v_code_other is not null and v_code is distinct from v_code_other then
      v_errors := v_errors || jsonb_build_array(
        'Questions row ' || v_row_no || ': question_id and public_code do not match'
      );
    elsif v_code is null and not v_qid_bad then
      v_code := v_code_other;
    end if;

    v_exp_1 := nullif(btrim(coalesce(v_row->>'exp_1', '')), '');
    v_exp_2 := nullif(btrim(coalesce(v_row->>'exp_2', '')), '');
    v_answer := nullif(btrim(coalesce(v_row->>'answers', '')), '');
    if v_subject_id is not null and v_kind in ('mcq', 'pyq_theory') and v_stem <> '' then
      v_legacy := public.admin_question_external_id(v_subject, v_kind, v_stem);
    else
      v_legacy := 'row-' || v_row_no::text;
    end if;
    v_fp := public.question_body_fingerprint(
      nullif(v_chapter, ''),
      nullif(v_topic, ''),
      nullif(v_marks, ''),
      v_opt_a, v_opt_b, v_opt_c, v_opt_d, v_correct,
      v_exp_1, v_exp_2, v_answer
    );

    insert into tmp_import_rows (
      row_no, legacy_id, subject_id, subject_name, question_text, kind, public_code, body_fp,
      option_a, option_b, option_c, option_d, correct_option,
      chapter_name, topic_name, marks,
      university_id, college_id, exam_year, exam_month, paper_name, exam_type,
      textbook_title, textbook_authors, textbook_edition, page, section_heading,
      explanation_text, explanation_deep, sample_answer_text,
      difficulty, required_plan, is_active,
      resource_title, resource_url, resource_source_label, resource_is_free
    ) values (
      v_row_no, v_legacy, v_subject_id, nullif(v_subject, ''), nullif(v_stem, ''), nullif(v_kind, ''),
      v_code, v_fp,
      v_opt_a, v_opt_b, v_opt_c, v_opt_d, v_correct,
      nullif(v_chapter, ''), nullif(v_topic, ''), nullif(v_marks, ''),
      v_university_id, v_college_id, v_year_int, v_month, nullif(v_paper, ''), v_exam,
      nullif(v_tb_title, ''),
      nullif(btrim(coalesce(v_row->>'textbook_authors', '')), ''),
      nullif(btrim(coalesce(v_row->>'textbook_edition', '')), ''),
      nullif(v_page, ''),
      nullif(btrim(coalesce(v_row->>'section_heading', '')), ''),
      v_exp_1, v_exp_2, v_answer,
      v_difficulty, v_plan, v_active,
      nullif(v_res_title, ''), nullif(v_res_url, ''),
      nullif(btrim(coalesce(v_row->>'resource_source_label', '')), ''),
      v_free
    );
  end loop;

  for v_grp in
    select legacy_id, min(row_no) as first_row
    from tmp_import_rows
    where legacy_id not like 'row-%'
    group by legacy_id
    having count(distinct body_fp) > 1
  loop
    v_errors := v_errors || jsonb_build_array(
      'Questions row ' || v_grp.first_row ||
      ': repeated subject/question_type/stem rows must use identical chapter, topic, marks, options, answers, and explanations'
    );
  end loop;

  for v_grp in
    select legacy_id, min(row_no) as first_row
    from tmp_import_rows
    where legacy_id not like 'row-%'
      and public_code is not null
    group by legacy_id
    having count(distinct public_code) > 1
  loop
    v_errors := v_errors || jsonb_build_array(
      'Questions row ' || v_grp.first_row ||
      ': rows with the same question text must use the same question_id'
    );
  end loop;

  for v_grp in
    select public_code, min(row_no) as first_row
    from tmp_import_rows
    where legacy_id not like 'row-%'
      and public_code is not null
    group by public_code
    having count(distinct legacy_id) > 1
  loop
    v_errors := v_errors || jsonb_build_array(
      'Questions row ' || v_grp.first_row ||
      ': question_id ' || v_grp.public_code || ' is used on more than one question'
    );
  end loop;

  create temporary table tmp_import_existing on commit drop as
  select
    q.id,
    q.public_code,
    q.external_id,
    public.admin_question_external_id(
      public.admin_question_subject_name(q.id),
      q.kind::text,
      q.question_text
    ) as legacy_id
  from public.questions q;

  for v_grp in
    select
      legacy_id,
      min(row_no) as first_row,
      count(*)::int as paper_count,
      (array_agg(question_text order by row_no))[1] as stem,
      (array_agg(public_code order by row_no) filter (where public_code is not null))[1] as public_code,
      (array_agg(subject_id order by row_no))[1] as subject_id
    from tmp_import_rows
    where legacy_id not like 'row-%'
    group by legacy_id
    order by min(row_no)
  loop
    select count(distinct body_fp) > 1
      into v_bad
    from tmp_import_rows
    where legacy_id = v_grp.legacy_id;
    if v_bad then
      continue;
    end if;
    select count(distinct public_code) > 1
      into v_bad
    from tmp_import_rows
    where legacy_id = v_grp.legacy_id
      and public_code is not null;
    if coalesce(v_bad, false) then
      continue;
    end if;

    v_existing := null;
    v_existing_code := null;
    if v_grp.public_code is not null then
      select q.id, q.public_code
        into v_existing, v_existing_code
      from public.questions q
      where q.public_code = v_grp.public_code;
      if v_existing is null then
        v_errors := v_errors || jsonb_build_array(
          'Questions row ' || v_grp.first_row || ': question_id ' || v_grp.public_code || ' does not exist'
        );
        continue;
      end if;
      v_other_code := null;
      select e.public_code
        into v_other_code
      from tmp_import_existing e
      where (e.legacy_id = v_grp.legacy_id or e.external_id = v_grp.legacy_id)
        and e.id is distinct from v_existing
      order by e.public_code nulls last
      limit 1;
      if found then
        v_errors := v_errors || jsonb_build_array(
          'Questions row ' || v_grp.first_row ||
          ': this question text already belongs to question_id ' ||
          coalesce(v_other_code, 'an existing question')
        );
        continue;
      end if;
    else
      select count(distinct e.id)::int
        into v_match_count
      from tmp_import_existing e
      where e.legacy_id = v_grp.legacy_id
         or e.external_id = v_grp.legacy_id;
      if v_match_count = 0 then
        v_existing := null;
      elsif v_match_count = 1 then
        select e.id, e.public_code
          into v_existing, v_existing_code
        from tmp_import_existing e
        where e.legacy_id = v_grp.legacy_id
           or e.external_id = v_grp.legacy_id
        limit 1;
      else
        v_errors := v_errors || jsonb_build_array(
          'Questions row ' || v_grp.first_row ||
          ': several questions share this text. Put a question_id on the row.'
        );
        continue;
      end if;
    end if;

    if v_existing is not null then
      select coalesce(
        (
          select t.subject_id
          from public.questions q
          join public.topics t on t.id = q.topic_id
          where q.id = v_existing
        ),
        (
          select ep.subject_id
          from public.question_appearances qa
          join public.exam_papers ep on ep.id = qa.exam_paper_id
          where qa.question_id = v_existing
          order by ep.exam_year desc nulls last
          limit 1
        )
      )
      into v_old_subject;

      if v_old_subject is distinct from v_grp.subject_id and exists (
        select 1
        from public.question_appearances qa
        join public.exam_papers ep on ep.id = qa.exam_paper_id
        where qa.question_id = v_existing
          and ep.exam_month is null
      ) then
        v_errors := v_errors || jsonb_build_array(
          'Questions row ' || v_grp.first_row ||
          ': set a month on every paper before changing the subject.'
        );
      end if;
    end if;

    insert into tmp_import_groups (
      legacy_id, first_row, existing_id, action, code, paper_count, stem, subject_id
    ) values (
      v_grp.legacy_id,
      v_grp.first_row,
      v_existing,
      case when v_existing is null then 'create' else 'update' end,
      v_existing_code,
      v_grp.paper_count,
      v_grp.stem,
      v_grp.subject_id
    );
  end loop;

  for v_grp in
    select existing_id, min(code) as code, min(first_row) as first_row
    from tmp_import_groups
    where existing_id is not null
    group by existing_id
    having count(*) > 1
  loop
    v_errors := v_errors || jsonb_build_array(
      'Questions row ' || v_grp.first_row ||
      ': question_id ' || coalesce(v_grp.code, '') || ' is used on more than one question'
    );
  end loop;

  if jsonb_array_length(v_errors) = 0 then
    select
      count(*) filter (where action = 'create'),
      count(*) filter (where action = 'update')
      into v_creates, v_updates
    from tmp_import_groups;

    if p_apply then
      for v_grp in
        select * from tmp_import_groups order by first_row
      loop
        select * into v_first
        from tmp_import_rows
        where legacy_id = v_grp.legacy_id
        order by row_no
        limit 1;

        v_body := jsonb_strip_nulls(jsonb_build_object(
          'subject_id', v_first.subject_id,
          'kind', v_first.kind,
          'question_text', v_first.question_text,
          'marks', v_first.marks,
          'difficulty', v_first.difficulty,
          'required_plan', v_first.required_plan,
          'is_active', v_first.is_active,
          'chapter_name', v_first.chapter_name,
          'topic_name', v_first.topic_name,
          'explanation_text', v_first.explanation_text,
          'explanation_deep', v_first.explanation_deep,
          'sample_answer', v_first.sample_answer_text
        ));
        if v_first.kind = 'mcq' then
          v_body := v_body || jsonb_build_object(
            'option_a', v_first.option_a,
            'option_b', v_first.option_b,
            'option_c', v_first.option_c,
            'option_d', v_first.option_d,
            'correct_option', v_first.correct_option
          );
        end if;
        if v_first.textbook_title is null then
          v_body := v_body || jsonb_build_object('textbook', null);
        else
          v_body := v_body || jsonb_build_object(
            'textbook', jsonb_build_object(
              'title', v_first.textbook_title,
              'authors', v_first.textbook_authors,
              'edition', v_first.textbook_edition,
              'page', v_first.page,
              'section_heading', v_first.section_heading
            )
          );
        end if;
        if v_first.resource_title is null then
          v_body := v_body || jsonb_build_object('resource', null);
        else
          v_body := v_body || jsonb_build_object(
            'resource', jsonb_build_object(
              'title', v_first.resource_title,
              'url', v_first.resource_url,
              'source_label', v_first.resource_source_label,
              'is_free', v_first.resource_is_free
            )
          );
        end if;

        v_seen := array[]::text[];
        v_sittings := '[]'::jsonb;
        for v_sitting in
          select *
          from tmp_import_rows
          where legacy_id = v_grp.legacy_id
          order by row_no
        loop
          v_sit_key := v_sitting.university_id::text || '|' ||
            coalesce(v_sitting.college_id::text, '') || '|' ||
            v_sitting.exam_year::text || '|' ||
            v_sitting.exam_month::text || '|' ||
            coalesce(v_sitting.exam_type, '') || '|' ||
            lower(coalesce(v_sitting.paper_name, ''));
          if v_sit_key = any(v_seen) then
            continue;
          end if;
          v_seen := array_append(v_seen, v_sit_key);
          v_sittings := v_sittings || jsonb_build_array(jsonb_build_object(
            'university_id', v_sitting.university_id,
            'college_id', v_sitting.college_id,
            'exam_year', v_sitting.exam_year,
            'exam_month', v_sitting.exam_month,
            'exam_type', v_sitting.exam_type,
            'paper_name', v_sitting.paper_name
          ));
        end loop;

        if v_grp.existing_id is null then
          v_body := v_body || jsonb_build_object('sitting', v_sittings->0);
        else
          v_body := v_body || jsonb_build_object('id', v_grp.existing_id);
        end if;

        v_saved := public.admin_save_question(v_body);
        v_question_id := (v_saved->>'id')::uuid;

        for v_sitting in
          select value as sit
          from jsonb_array_elements(v_sittings)
        loop
          perform public.admin_save_appearance(jsonb_build_object(
            'question_id', v_question_id,
            'university_id', v_sitting.sit->>'university_id',
            'college_id', v_sitting.sit->>'college_id',
            'exam_year', v_sitting.sit->>'exam_year',
            'exam_month', v_sitting.sit->>'exam_month',
            'exam_type', v_sitting.sit->>'exam_type',
            'paper_name', v_sitting.sit->>'paper_name'
          ));
        end loop;

        update tmp_import_groups
        set code = (
          select q.public_code from public.questions q where q.id = v_question_id
        )
        where legacy_id = v_grp.legacy_id;
      end loop;

      perform public.admin_log_action(
        'import_questions',
        null,
        jsonb_build_object(
          'creates', v_creates,
          'updates', v_updates,
          'rows', v_content
        )
      );
      v_applied := true;

      select coalesce(jsonb_agg(
        jsonb_build_object(
          'row_no', r.row_no,
          'question_id', g.code
        )
        order by r.row_no
      ), '[]'::jsonb)
        into v_codes
      from tmp_import_rows r
      join tmp_import_groups g on g.legacy_id = r.legacy_id;
    end if;

    select coalesce(jsonb_agg(
      jsonb_build_object(
        'row_no', g.first_row,
        'action', g.action,
        'question_id', g.code,
        'papers', g.paper_count,
        'question_text', left(regexp_replace(g.stem, '\s+', ' ', 'g'), 140)
      )
      order by g.first_row
    ), '[]'::jsonb)
      into v_questions
    from tmp_import_groups g;
  end if;

  return jsonb_build_object(
    'ok', jsonb_array_length(v_errors) = 0,
    'applied', v_applied,
    'errors', v_errors,
    'creates', case when jsonb_array_length(v_errors) = 0 then v_creates else 0 end,
    'updates', case when jsonb_array_length(v_errors) = 0 then v_updates else 0 end,
    'row_count', (select count(*) from tmp_import_rows),
    'questions', v_questions,
    'codes', v_codes
  );
end;
$$;

comment on function public.admin_import_questions(jsonb, jsonb, boolean) is
  'Validates a Questions sheet and, when p_apply is true, creates or updates those questions. Does not delete questions missing from the file.';

revoke all on function public.admin_import_questions(jsonb, jsonb, boolean) from public, anon, authenticated;
grant execute on function public.admin_import_questions(jsonb, jsonb, boolean) to authenticated, service_role;
