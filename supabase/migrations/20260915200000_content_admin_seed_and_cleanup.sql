-- Admin catalog seed, subject → MBBS year map, orphan cleanup, and CSV sync
-- wiring so new subjects get the correct year without a CSV phase column.

-- ---------------------------------------------------------------------------
-- Subject → year map (source of truth for CSV sync)
-- ---------------------------------------------------------------------------

create table if not exists public.subject_phase_defaults (
  subject_name text primary key,
  phase_code public.mbbs_phase_code not null,
  display_order int not null default 0
);

comment on table public.subject_phase_defaults is
  'Maps editor subject_name to MBBS year. CSV sync reads this; not a sheet column.';

-- University-exam subjects only. Allied topics (Ortho, Dermatology,
-- Psychiatry, Anesthesia, Radiology) stay inside Medicine/Surgery papers.
-- Already-applied databases are corrected by
-- 20261010130000_mbbs_subject_catalog.sql.
insert into public.subject_phase_defaults (subject_name, phase_code, display_order) values
  ('Anatomy', 'year1', 1),
  ('Physiology', 'year1', 2),
  ('Biochemistry', 'year1', 3),
  ('Pathology', 'year2', 4),
  ('Pharmacology', 'year2', 5),
  ('Microbiology', 'year2', 6),
  ('FMT', 'year3', 7),
  ('PSM', 'year3', 8),
  ('Ophthalmology', 'year3', 9),
  ('ENT', 'year3', 10),
  ('Medicine', 'year4', 11),
  ('Surgery', 'year4', 12),
  ('OBGYN', 'year4', 13),
  ('Pediatrics', 'year4', 14)
on conflict (subject_name) do update
  set phase_code = excluded.phase_code,
      display_order = excluded.display_order;

-- Apply year tags to existing subjects (case-insensitive name match).
update public.subjects s
set mbbs_phase_id = p.id,
    display_order = d.display_order
from public.subject_phase_defaults d
join public.mbbs_phases p on p.code = d.phase_code
where lower(s.name) = lower(d.subject_name);

-- Ensure catalog subjects exist even before the first CSV sync.
insert into public.subjects (name, display_order, mbbs_phase_id)
select d.subject_name, d.display_order, p.id
from public.subject_phase_defaults d
join public.mbbs_phases p on p.code = d.phase_code
where not exists (
  select 1 from public.subjects s where lower(s.name) = lower(d.subject_name)
);

-- ---------------------------------------------------------------------------
-- Universities + colleges (admin seed; mirrors content/admin/*.csv)
-- ---------------------------------------------------------------------------

insert into public.universities (code, name, state, slug) values
  ('KUHS', 'Kerala University of Health Sciences', 'Kerala', 'kuhs'),
  ('RGUHS', 'Rajiv Gandhi University of Health Sciences', 'Karnataka', 'rguhs'),
  ('NTRUHS', 'Dr. NTR University of Health Sciences', 'Andhra Pradesh', 'ntruhs'),
  ('KNRUHS', 'Kaloji Narayana Rao University of Health Sciences', 'Telangana', 'knruhs'),
  ('TNMGRMU', 'Tamil Nadu Dr. M.G.R. Medical University', 'Tamil Nadu', 'tnmgrmu'),
  ('WBUHS', 'West Bengal University of Health Sciences', 'West Bengal', 'wbuhs'),
  ('RUHS', 'Rajasthan University of Health Sciences', 'Rajasthan', 'ruhs'),
  ('MUHS', 'Maharashtra University of Health Sciences', 'Maharashtra', 'muhs')
on conflict (code) do update
  set name = excluded.name,
      state = excluded.state,
      slug = excluded.slug;

insert into public.colleges (university_id, name)
select u.id, c.name
from public.universities u
join (values
  ('KUHS', 'Government Medical College, Thiruvananthapuram'),
  ('KUHS', 'Government Medical College, Kozhikode'),
  ('KUHS', 'Government Medical College, Kottayam'),
  ('KUHS', 'Government Medical College, Thrissur'),
  ('KUHS', 'Amrita School of Medicine, Kochi'),
  ('KUHS', 'Jubilee Mission Medical College, Thrissur'),
  ('KUHS', 'Malankara Orthodox Syrian Church Medical College, Kolenchery'),
  ('KUHS', 'Pushpagiri Institute of Medical Sciences, Thiruvalla'),
  ('KUHS', 'Other / not listed'),
  ('RGUHS', 'Bangalore Medical College and Research Institute'),
  ('RGUHS', 'Mysore Medical College and Research Institute'),
  ('RGUHS', 'Other / not listed'),
  ('NTRUHS', 'Andhra Medical College, Visakhapatnam'),
  ('NTRUHS', 'Guntur Medical College'),
  ('NTRUHS', 'Other / not listed'),
  ('KNRUHS', 'Osmania Medical College, Hyderabad'),
  ('KNRUHS', 'Gandhi Medical College, Secunderabad'),
  ('KNRUHS', 'Other / not listed'),
  ('TNMGRMU', 'Madras Medical College, Chennai'),
  ('TNMGRMU', 'Stanley Medical College, Chennai'),
  ('TNMGRMU', 'Other / not listed'),
  ('WBUHS', 'Medical College, Kolkata'),
  ('WBUHS', 'Nil Ratan Sircar Medical College, Kolkata'),
  ('WBUHS', 'Other / not listed'),
  ('RUHS', 'SMS Medical College, Jaipur'),
  ('RUHS', 'Dr. SN Medical College, Jodhpur'),
  ('RUHS', 'Other / not listed'),
  ('MUHS', 'Grant Medical College, Mumbai'),
  ('MUHS', 'B.J. Government Medical College, Pune'),
  ('MUHS', 'Other / not listed')
) as c(code, name) on lower(u.code) = lower(c.code)
on conflict (university_id, name) do nothing;

-- Profiles pointing at universities outside the seeded catalog (e.g. IPU)
-- keep accounts but clear academic FKs so onboarding can be re-chosen.
update public.profiles p
set university_id = null,
    college_id = null
where p.university_id is not null
  and not exists (
    select 1 from public.universities u
    where u.id = p.university_id
      and u.code in (
        'KUHS', 'RGUHS', 'NTRUHS', 'KNRUHS', 'TNMGRMU', 'WBUHS', 'RUHS', 'MUHS'
      )
  );

delete from public.colleges c
where not exists (
  select 1 from public.universities u
  where u.id = c.university_id
    and u.code in (
      'KUHS', 'RGUHS', 'NTRUHS', 'KNRUHS', 'TNMGRMU', 'WBUHS', 'RUHS', 'MUHS'
    )
);

delete from public.universities u
where u.code not in (
  'KUHS', 'RGUHS', 'NTRUHS', 'KNRUHS', 'TNMGRMU', 'WBUHS', 'RUHS', 'MUHS'
)
and not exists (select 1 from public.profiles p where p.university_id = u.id)
and not exists (select 1 from public.exam_papers ep where ep.university_id = u.id);

-- ---------------------------------------------------------------------------
-- Orphan content cleanup (safe: only unused rows)
-- ---------------------------------------------------------------------------

delete from public.exam_papers ep
where not exists (
  select 1 from public.question_appearances qa where qa.exam_paper_id = ep.id
);

delete from public.textbooks tb
where not exists (
  select 1 from public.question_textbook_refs r where r.textbook_id = tb.id
);

delete from public.lesson_resources lr
where not exists (
  select 1 from public.lessons l where l.id = lr.lesson_id
);

delete from public.lessons l
where not exists (
  select 1 from public.questions q where q.lesson_id = l.id
)
and not exists (
  select 1 from public.lesson_progress lp where lp.lesson_id = l.id
)
and not exists (
  select 1 from public.lesson_bookmarks lb where lb.lesson_id = l.id
);

delete from public.topics t
where not exists (
  select 1 from public.lessons l where l.topic_id = t.id
)
and not exists (
  select 1 from public.questions q where q.topic_id = t.id
);

-- ---------------------------------------------------------------------------
-- Helper used by sync_content_csv: create/tag subject from the year map
-- ---------------------------------------------------------------------------

create or replace function public.ensure_csv_subject(p_subject_name text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_phase_id uuid;
  v_order int;
  v_canonical text;
begin
  select s.id into v_id
  from public.subjects s
  where lower(s.name) = lower(btrim(p_subject_name))
  order by s.id
  limit 1;

  select d.subject_name, p.id, d.display_order
    into v_canonical, v_phase_id, v_order
  from public.subject_phase_defaults d
  join public.mbbs_phases p on p.code = d.phase_code
  where lower(d.subject_name) = lower(btrim(p_subject_name))
  limit 1;

  if v_phase_id is null then
    raise exception 'Unknown subject "%" — add it to subject_phase_defaults', p_subject_name;
  end if;

  if v_id is null then
    insert into public.subjects (name, display_order, mbbs_phase_id)
    values (v_canonical, v_order, v_phase_id)
    returning id into v_id;
  else
    update public.subjects
    set mbbs_phase_id = coalesce(mbbs_phase_id, v_phase_id),
        display_order = case when display_order = 0 then v_order else display_order end,
        name = v_canonical
    where id = v_id;
  end if;

  return v_id;
end;
$$;

revoke all on function public.ensure_csv_subject(text) from public;
revoke all on function public.ensure_csv_subject(text) from anon, authenticated;
grant execute on function public.ensure_csv_subject(text) to service_role;

-- Wire subject validation + ensure_csv_subject into sync_content_csv without
-- rewriting the whole importer: wrap body via replace of the subject blocks.
-- Full function body is recreated below from 20260915190000 with those edits.

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
  v_paper text;
  v_uni text;
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
  v_paper_id uuid;
  v_textbook_id uuid;
  v_external_id text;
  v_paper_external_id text;
  v_textbook_key text;
  v_existing boolean;
  v_key text;
  v_allowed_columns text[] := array[
    '_row_number', 'subject_name', 'question_text', 'option_a', 'option_b',
    'option_c', 'option_d', 'correct_option', 'kind', 'topic_name',
    'lesson_name', 'marks', 'university_code', 'exam_year', 'paper_name',
    'exam_type', 'textbook_title', 'textbook_authors', 'textbook_edition',
    'page', 'section_heading', 'explanation_text', 'sample_answer_text',
    'difficulty', 'required_plan', 'is_active', 'resource_title',
    'resource_url', 'resource_source_label', 'resource_is_free'
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
    topic_name text,
    lesson_name text,
    marks text,
    university_code text,
    exam_year text,
    paper_name text,
    exam_type text,
    textbook_title text,
    textbook_authors text,
    textbook_edition text,
    page text,
    section_heading text,
    explanation_text text,
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
    v_kind := lower(btrim(coalesce(v_row->>'kind', '')));
    if v_kind = '' then
      if concat_ws('',
        btrim(coalesce(v_row->>'option_a', '')),
        btrim(coalesce(v_row->>'option_b', '')),
        btrim(coalesce(v_row->>'option_c', '')),
        btrim(coalesce(v_row->>'option_d', '')),
        btrim(coalesce(v_row->>'correct_option', ''))
      ) = '' then
        v_kind := 'pyq_theory';
      else
        v_kind := 'mcq';
      end if;
    end if;

    if v_subject = '' then
      v_errors := v_errors || jsonb_build_array('Questions row ' || v_row_no || ': subject_name is required');
    end if;
    if v_stem = '' then
      v_errors := v_errors || jsonb_build_array('Questions row ' || v_row_no || ': question_text is required');
    end if;
    if v_kind not in ('mcq', 'pyq_theory') then
      v_errors := v_errors || jsonb_build_array('Questions row ' || v_row_no || ': kind must be mcq or pyq_theory');
    end if;

    if v_kind = 'mcq' then
      if btrim(coalesce(v_row->>'option_a', '')) = '' then
        v_errors := v_errors || jsonb_build_array('Questions row ' || v_row_no || ': option_a is required for MCQ');
      end if;
      if btrim(coalesce(v_row->>'option_b', '')) = '' then
        v_errors := v_errors || jsonb_build_array('Questions row ' || v_row_no || ': option_b is required for MCQ');
      end if;
      if btrim(coalesce(v_row->>'option_c', '')) = '' then
        v_errors := v_errors || jsonb_build_array('Questions row ' || v_row_no || ': option_c is required for MCQ');
      end if;
      if btrim(coalesce(v_row->>'option_d', '')) = '' then
        v_errors := v_errors || jsonb_build_array('Questions row ' || v_row_no || ': option_d is required for MCQ');
      end if;
      if upper(btrim(coalesce(v_row->>'correct_option', ''))) not in ('A', 'B', 'C', 'D') then
        v_errors := v_errors || jsonb_build_array('Questions row ' || v_row_no || ': correct_option must be A, B, C, or D');
      end if;
    elsif concat_ws('',
      btrim(coalesce(v_row->>'option_a', '')),
      btrim(coalesce(v_row->>'option_b', '')),
      btrim(coalesce(v_row->>'option_c', '')),
      btrim(coalesce(v_row->>'option_d', '')),
      btrim(coalesce(v_row->>'correct_option', ''))
    ) <> '' then
      v_errors := v_errors || jsonb_build_array('Questions row ' || v_row_no || ': theory rows must leave MCQ option/key cells blank');
    end if;

    if btrim(coalesce(v_row->>'lesson_name', '')) <> ''
       and btrim(coalesce(v_row->>'topic_name', '')) = '' then
      v_errors := v_errors || jsonb_build_array('Questions row ' || v_row_no || ': lesson_name requires topic_name');
    end if;

    v_year := btrim(coalesce(v_row->>'exam_year', ''));
    v_paper := btrim(coalesce(v_row->>'paper_name', ''));
    v_uni := btrim(coalesce(v_row->>'university_code', ''));
    if (v_year = '') <> (v_paper = '') then
      v_errors := v_errors || jsonb_build_array('Questions row ' || v_row_no || ': exam_year and paper_name must be filled together');
    end if;
    if (v_year = '') <> (v_uni = '') then
      v_errors := v_errors || jsonb_build_array('Questions row ' || v_row_no || ': university_code must be filled together with exam_year and paper_name');
    end if;
    if v_year <> '' then
      if v_year !~ '^[0-9]{4}$' then
        v_errors := v_errors || jsonb_build_array('Questions row ' || v_row_no || ': exam_year must be a four-digit year');
      elsif v_year::int < 1900 or v_year::int > 2200 then
        v_errors := v_errors || jsonb_build_array('Questions row ' || v_row_no || ': exam_year must be between 1900 and 2200');
      end if;
    end if;
    if lower(coalesce(nullif(btrim(coalesce(v_row->>'exam_type', '')), ''), 'university')) not in ('university', 'internal') then
      v_errors := v_errors || jsonb_build_array('Questions row ' || v_row_no || ': exam_type must be university or internal');
    end if;

    v_marks := btrim(coalesce(v_row->>'marks', ''));
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

    if lower(coalesce(nullif(btrim(coalesce(v_row->>'difficulty', '')), ''), 'medium')) not in ('easy', 'medium', 'hard') then
      v_errors := v_errors || jsonb_build_array('Questions row ' || v_row_no || ': difficulty must be easy, medium, or hard');
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
      v_kind || '|' ||
      lower(regexp_replace(v_stem, '\s+', ' ', 'g'))
    ), 1, 24));

    insert into tmp_content_rows values (
      v_row_no, v_external_id, v_subject, v_stem, v_kind,
      nullif(btrim(coalesce(v_row->>'option_a', '')), ''),
      nullif(btrim(coalesce(v_row->>'option_b', '')), ''),
      nullif(btrim(coalesce(v_row->>'option_c', '')), ''),
      nullif(btrim(coalesce(v_row->>'option_d', '')), ''),
      nullif(upper(btrim(coalesce(v_row->>'correct_option', ''))), ''),
      nullif(btrim(coalesce(v_row->>'topic_name', '')), ''),
      nullif(btrim(coalesce(v_row->>'lesson_name', '')), ''),
      nullif(v_marks, ''),
      nullif(upper(v_uni), ''),
      nullif(v_year, ''), nullif(v_paper, ''),
      lower(coalesce(nullif(btrim(coalesce(v_row->>'exam_type', '')), ''), 'university')),
      nullif(v_tb_title, ''),
      nullif(btrim(coalesce(v_row->>'textbook_authors', '')), ''),
      nullif(btrim(coalesce(v_row->>'textbook_edition', '')), ''),
      nullif(v_page, ''),
      nullif(btrim(coalesce(v_row->>'section_heading', '')), ''),
      nullif(btrim(coalesce(v_row->>'explanation_text', '')), ''),
      nullif(btrim(coalesce(v_row->>'sample_answer_text', '')), ''),
      lower(coalesce(nullif(btrim(coalesce(v_row->>'difficulty', '')), ''), 'medium')),
      lower(coalesce(nullif(btrim(coalesce(v_row->>'required_plan', '')), ''), 'free')),
      upper(coalesce(nullif(btrim(coalesce(v_row->>'is_active', '')), ''), 'TRUE')),
      nullif(v_resource_title, ''), nullif(v_resource_url, ''),
      nullif(btrim(coalesce(v_row->>'resource_source_label', '')), ''),
      upper(coalesce(nullif(btrim(coalesce(v_row->>'resource_is_free', '')), ''), 'TRUE'))
    );
    v_row_no := v_row_no + 1;
  end loop;

  -- Repeated rows intentionally add appearances/refs/resources, but their
  -- question body must agree.
  for v_rec in
    select external_id, min(row_no) as first_row
    from tmp_content_rows
    group by external_id
    having count(distinct concat_ws('|', coalesce(option_a, ''), coalesce(option_b, ''),
      coalesce(option_c, ''), coalesce(option_d, ''), coalesce(correct_option, ''),
      coalesce(topic_name, ''), coalesce(lesson_name, ''), coalesce(marks, ''),
      coalesce(explanation_text, ''), coalesce(sample_answer_text, ''))) > 1
  loop
    v_errors := v_errors || jsonb_build_array(
      'Questions row ' || v_rec.first_row || ': repeated subject/kind/stem rows must use identical tags, marks, options, and answers'
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

  for v_rec in
    select distinct university_code, min(row_no) as first_row
    from tmp_content_rows
    where university_code is not null
    group by university_code
  loop
    if not exists (
      select 1 from public.universities u
      where lower(u.code) = lower(v_rec.university_code)
    ) then
      v_errors := v_errors || jsonb_build_array(
        'Questions row ' || v_rec.first_row || ': university_code "' ||
        v_rec.university_code || '" does not exist'
      );
    end if;
  end loop;

  for v_rec in
    select distinct subject_name, min(row_no) as first_row
    from tmp_content_rows
    group by subject_name
  loop
    if not exists (
      select 1 from public.subject_phase_defaults d
      where lower(d.subject_name) = lower(v_rec.subject_name)
    ) then
      v_errors := v_errors || jsonb_build_array(
        'Questions row ' || v_rec.first_row || ': unknown subject_name "' ||
        v_rec.subject_name ||
        '" — add it to subject_phase_defaults (MBBS year map)'
      );
    end if;
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

  -- One canonical body row per generated question identity.
  for v_rec in
    select distinct on (external_id) *
    from tmp_content_rows
    order by external_id, (topic_name is not null) desc, row_no
  loop
    v_subject_id := public.ensure_csv_subject(v_rec.subject_name);

    v_topic_id := null;
    if v_rec.topic_name is not null then
      select id into v_topic_id from public.topics
      where subject_id = v_subject_id and lower(name) = lower(v_rec.topic_name)
      order by id limit 1;
      if v_topic_id is null then
        insert into public.topics (subject_id, name, display_order)
        values (
          v_subject_id, v_rec.topic_name,
          (select coalesce(max(display_order), 0) + 1 from public.topics where subject_id = v_subject_id)
        ) returning id into v_topic_id;
      end if;
    end if;

    v_lesson_id := null;
    if v_rec.lesson_name is not null then
      select id into v_lesson_id from public.lessons
      where topic_id = v_topic_id and lower(name) = lower(v_rec.lesson_name)
      order by id limit 1;
      if v_lesson_id is null then
        insert into public.lessons (
          topic_id, external_id, name, display_order, required_plan, is_active
        ) values (
          v_topic_id,
          'CSV-L-' || upper(substr(md5(v_subject_id::text || '|' || v_topic_id::text || '|' || lower(v_rec.lesson_name)), 1, 24)),
          v_rec.lesson_name,
          (select coalesce(max(display_order), 0) + 1 from public.lessons where topic_id = v_topic_id),
          v_rec.required_plan::public.plan_tier,
          v_rec.is_active in ('TRUE', 'YES', '1')
        ) returning id into v_lesson_id;
      end if;
    end if;

    select exists(select 1 from public.questions where external_id = v_rec.external_id)
      into v_existing;
    insert into public.questions (
      external_id, topic_id, lesson_id, kind, question_text,
      option_a, option_b, option_c, option_d, correct_option,
      explanation_text, difficulty, marks, required_plan, is_active,
      content_sync_source
    ) values (
      v_rec.external_id, v_topic_id, v_lesson_id, v_rec.kind::public.question_kind,
      v_rec.question_text, v_rec.option_a, v_rec.option_b, v_rec.option_c,
      v_rec.option_d, v_rec.correct_option, v_rec.explanation_text,
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

    -- Child sets are replaced from this snapshot below.
    delete from public.question_appearances where question_id = v_question_id;
    delete from public.question_textbook_refs where question_id = v_question_id;
    delete from public.question_resources where question_id = v_question_id;
  end loop;

  for v_rec in select * from tmp_content_rows order by row_no
  loop
    select id into v_question_id from public.questions where external_id = v_rec.external_id;
    v_subject_id := public.ensure_csv_subject(v_rec.subject_name);

    if v_rec.exam_year is not null then
      select id into v_university_id from public.universities
      where lower(code) = lower(v_rec.university_code) order by id limit 1;
      v_paper_external_id := 'CSV-EP-' || upper(substr(md5(
        lower(v_rec.university_code) || '|' || v_subject_id::text || '|' ||
        v_rec.exam_year || '|' || lower(v_rec.paper_name) || '|' || v_rec.exam_type
      ), 1, 24));
      insert into public.exam_papers (
        external_id, university_id, subject_id, exam_year, paper_name, exam_type
      ) values (
        v_paper_external_id, v_university_id, v_subject_id,
        v_rec.exam_year::int, v_rec.paper_name, v_rec.exam_type
      )
      on conflict (external_id) do update set
        university_id = excluded.university_id,
        subject_id = excluded.subject_id,
        exam_year = excluded.exam_year,
        paper_name = excluded.paper_name,
        exam_type = excluded.exam_type
      returning id into v_paper_id;
      insert into public.question_appearances (question_id, exam_paper_id)
      values (v_question_id, v_paper_id)
      on conflict do nothing;
    end if;

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

  -- An attempt against a changed test cannot retain a trustworthy review.
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


revoke all on function public.sync_content_csv(jsonb, boolean) from public;
revoke all on function public.sync_content_csv(jsonb, boolean) from anon, authenticated;
grant execute on function public.sync_content_csv(jsonb, boolean) to service_role;

comment on function public.sync_content_csv(jsonb, boolean) is
  'Validates/previews or transactionally applies the one-file Questions CSV snapshot. Subjects get MBBS year from subject_phase_defaults.';
