-- Excel round-trip for the website questions list.
-- One selected question is one sheet row (its latest complete paper).
-- question_id is questions.public_code. Uploading the file through
-- admin_import_questions updates that question. Other papers stay.

create or replace function public.admin_export_questions(p_ids jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_temp, public
as $$
declare
  v_ids uuid[];
  v_count int;
  v_headers jsonb := jsonb_build_array(
    'course', 'state',
    'university_alias', 'university_name',
    'college_alias', 'college_name',
    'exam_type', 'year', 'month', 'paper_number',
    'subject_name', 'chapter_name', 'topic_name',
    'question_type', 'marks', 'question_id', 'question_text',
    'option_a', 'option_b', 'option_c', 'option_d', 'correct_option',
    'answers', 'exp_1', 'exp_2',
    'textbook_title', 'textbook_authors', 'textbook_edition',
    'page', 'section_heading',
    'difficulty', 'required_plan', 'is_active',
    'resource_title', 'resource_url', 'resource_source_label', 'resource_is_free'
  );
  v_rows jsonb := '[]'::jsonb;
  v_skipped jsonb := '[]'::jsonb;
begin
  perform public.assert_admin();

  if p_ids is null or jsonb_typeof(p_ids) <> 'array' then
    raise exception 'Choose at least one question.';
  end if;

  begin
    select coalesce(array_agg(distinct id), '{}'::uuid[])
      into v_ids
    from (
      select btrim(value) as raw
      from jsonb_array_elements_text(p_ids) as value
    ) cleaned
    cross join lateral (
      select cleaned.raw::uuid as id
      where cleaned.raw <> ''
    ) parsed;
  exception
    when invalid_text_representation then
      raise exception 'Choose questions from the list.';
  end;

  v_count := coalesce(array_length(v_ids, 1), 0);
  if v_count = 0 then
    raise exception 'Choose at least one question.';
  end if;
  if v_count > 300 then
    raise exception 'Select at most 300 questions.';
  end if;

  with wanted as (
    select id from unnest(v_ids) as id
  ),
  papers as (
    select distinct on (qa.question_id)
      qa.question_id,
      coalesce(u.state, '') as state,
      u.code as university_alias,
      u.name as university_name,
      case
        when ep.college_id is null then ''
        else c.short_form
      end as college_alias,
      case
        when ep.college_id is null then ''
        else c.name
      end as college_name,
      coalesce(public.admin_exam_type_label(ep.exam_type), '') as exam_type,
      ep.exam_year::text as year,
      coalesce(public.admin_month_name(ep.exam_month::int), '') as month,
      coalesce(ep.paper_name, '') as paper_number,
      s.name as subject_name
    from public.question_appearances qa
    join public.exam_papers ep on ep.id = qa.exam_paper_id
    join public.universities u on u.id = ep.university_id
    join public.subjects s on s.id = ep.subject_id
    left join public.colleges c on c.id = ep.college_id
    where qa.question_id = any(v_ids)
      and ep.exam_year between 1990 and 2100
      and ep.exam_month between 1 and 12
      and ep.exam_type in ('prof', 'supply', 'pre_prof', 'internal')
      and nullif(btrim(u.code), '') is not null
      and nullif(btrim(u.name), '') is not null
      and (
        ep.college_id is null
        or (
          nullif(btrim(c.short_form), '') is not null
          and nullif(btrim(c.name), '') is not null
        )
      )
    order by qa.question_id, ep.exam_year desc, ep.exam_month desc, ep.id
  ),
  ready as (
    select
      q.id,
      q.public_code,
      q.kind::text as kind,
      coalesce(topic_subject.name, p.subject_name, '') as subject_name,
      coalesce(top.name, '') as chapter_name,
      coalesce(les.name, '') as topic_name,
      p.state,
      p.university_alias,
      p.university_name,
      p.college_alias,
      p.college_name,
      p.exam_type,
      p.year,
      p.month,
      p.paper_number,
      case
        when q.id is null then 'Question not found.'
        when q.public_code is null then 'This question has no id.'
        when nullif(btrim(coalesce(topic_subject.name, p.subject_name, '')), '') is null
          then 'This question has no subject.'
        when q.kind::text not in ('mcq', 'pyq_theory')
          then 'This question type cannot be exported.'
        when coalesce(q.difficulty::text, 'should') not in ('must', 'should', 'could')
          then 'Difficulty must be must, should, or could.'
        when q.required_plan::text not in ('free', 'pro', 'elite')
          then 'Plan must be free, pro, or elite.'
        when p.question_id is null
          then 'This question has no paper with a university, year, and month.'
        when (nullif(btrim(coalesce(top.name, '')), '') is null)
          and nullif(btrim(coalesce(les.name, '')), '') is not null
          then 'Add a chapter before a topic.'
        when q.kind::text = 'mcq' and (
          nullif(btrim(coalesce(q.option_a, '')), '') is null
          or nullif(btrim(coalesce(q.option_b, '')), '') is null
          or nullif(btrim(coalesce(q.option_c, '')), '') is null
          or nullif(btrim(coalesce(q.option_d, '')), '') is null
          or upper(btrim(coalesce(q.correct_option, ''))) not in ('A', 'B', 'C', 'D')
        ) then 'MCQ questions need four options and a correct option.'
        when (nullif(btrim(coalesce(tb.title, '')), '') is null)
          <> (tb.page is null or tb.page <= 0)
          then 'Textbook title and page must both be filled.'
        when (nullif(btrim(coalesce(res.title, '')), '') is null)
          <> (nullif(btrim(coalesce(res.url, '')), '') is null)
          then 'Link title and URL must both be filled.'
        when nullif(btrim(coalesce(res.url, '')), '') is not null
          and btrim(res.url) !~ '^https://'
          then 'Link URL must start with https://.'
        when nullif(btrim(coalesce(res.source_label, '')), '') is not null
          and nullif(btrim(coalesce(res.title, '')), '') is null
          then 'Link title and URL must both be filled.'
        else null
      end as skip_reason,
      public.sheet_marks_text(q.marks) as marks,
      coalesce(q.question_text, '') as question_text,
      case when q.kind::text = 'mcq' then coalesce(q.option_a, '') else '' end as option_a,
      case when q.kind::text = 'mcq' then coalesce(q.option_b, '') else '' end as option_b,
      case when q.kind::text = 'mcq' then coalesce(q.option_c, '') else '' end as option_c,
      case when q.kind::text = 'mcq' then coalesce(q.option_d, '') else '' end as option_d,
      case
        when q.kind::text = 'mcq' then upper(coalesce(q.correct_option, ''))
        else ''
      end as correct_option,
      coalesce(sa.body, '') as answers,
      coalesce(q.explanation_text, '') as exp_1,
      coalesce(q.explanation_deep, '') as exp_2,
      case
        when nullif(btrim(coalesce(tb.title, '')), '') is not null and tb.page > 0
          then tb.title
        else ''
      end as textbook_title,
      case
        when nullif(btrim(coalesce(tb.title, '')), '') is not null and tb.page > 0
          then coalesce(tb.authors, '')
        else ''
      end as textbook_authors,
      case
        when nullif(btrim(coalesce(tb.title, '')), '') is not null and tb.page > 0
          then coalesce(tb.edition, '')
        else ''
      end as textbook_edition,
      case
        when nullif(btrim(coalesce(tb.title, '')), '') is not null and tb.page > 0
          then tb.page::text
        else ''
      end as page,
      case
        when nullif(btrim(coalesce(tb.title, '')), '') is not null and tb.page > 0
          then coalesce(tb.section_heading, '')
        else ''
      end as section_heading,
      coalesce(q.difficulty::text, 'should') as difficulty,
      q.required_plan::text as required_plan,
      case when q.is_active then 'TRUE' else 'FALSE' end as is_active,
      case
        when nullif(btrim(coalesce(res.title, '')), '') is not null
          and nullif(btrim(coalesce(res.url, '')), '') is not null
          and btrim(res.url) ~ '^https://'
          then res.title
        else ''
      end as resource_title,
      case
        when nullif(btrim(coalesce(res.title, '')), '') is not null
          and nullif(btrim(coalesce(res.url, '')), '') is not null
          and btrim(res.url) ~ '^https://'
          then btrim(res.url)
        else ''
      end as resource_url,
      case
        when nullif(btrim(coalesce(res.title, '')), '') is not null
          and nullif(btrim(coalesce(res.url, '')), '') is not null
          and btrim(res.url) ~ '^https://'
          then coalesce(res.source_label, '')
        else ''
      end as resource_source_label,
      case
        when nullif(btrim(coalesce(res.title, '')), '') is not null
          and nullif(btrim(coalesce(res.url, '')), '') is not null
          and btrim(res.url) ~ '^https://'
          then case when res.is_free then 'TRUE' else 'FALSE' end
        else ''
      end as resource_is_free
    from wanted w
    left join public.questions q on q.id = w.id
    left join papers p on p.question_id = q.id
    left join public.question_sample_answers sa on sa.question_id = q.id
    left join public.topics top on top.id = q.topic_id
    left join public.lessons les on les.id = q.lesson_id
    left join lateral (
      select s.name
      from public.topics t
      join public.subjects s on s.id = t.subject_id
      where t.id = q.topic_id
    ) topic_subject on true
    left join lateral (
      select tb.title, tb.authors, tb.edition, r.page, r.section_heading
      from public.question_textbook_refs r
      join public.textbooks tb on tb.id = r.textbook_id
      where r.question_id = q.id
      order by r.page
      limit 1
    ) tb on true
    left join lateral (
      select qr.title, qr.url, qr.source_label, qr.is_free
      from public.question_resources qr
      where qr.question_id = q.id
      order by qr.display_order, qr.url
      limit 1
    ) res on true
  )
  select
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'course', '',
          'state', r.state,
          'university_alias', r.university_alias,
          'university_name', r.university_name,
          'college_alias', r.college_alias,
          'college_name', r.college_name,
          'exam_type', r.exam_type,
          'year', r.year,
          'month', r.month,
          'paper_number', r.paper_number,
          'subject_name', r.subject_name,
          'chapter_name', r.chapter_name,
          'topic_name', r.topic_name,
          'question_type', r.kind,
          'marks', r.marks,
          'question_id', r.public_code,
          'question_text', r.question_text,
          'option_a', r.option_a,
          'option_b', r.option_b,
          'option_c', r.option_c,
          'option_d', r.option_d,
          'correct_option', r.correct_option,
          'answers', r.answers,
          'exp_1', r.exp_1,
          'exp_2', r.exp_2,
          'textbook_title', r.textbook_title,
          'textbook_authors', r.textbook_authors,
          'textbook_edition', r.textbook_edition,
          'page', r.page,
          'section_heading', r.section_heading,
          'difficulty', r.difficulty,
          'required_plan', r.required_plan,
          'is_active', r.is_active,
          'resource_title', r.resource_title,
          'resource_url', r.resource_url,
          'resource_source_label', r.resource_source_label,
          'resource_is_free', r.resource_is_free
        )
        order by r.public_code
      )
      from ready r
      where r.skip_reason is null
    ), '[]'::jsonb),
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', r.id,
          'public_code', r.public_code,
          'reason', r.skip_reason
        )
        order by r.public_code nulls last, r.id
      )
      from ready r
      where r.skip_reason is not null
    ), '[]'::jsonb)
  into v_rows, v_skipped;

  return jsonb_build_object(
    'headers', v_headers,
    'rows', v_rows,
    'skipped', v_skipped
  );
end;
$$;

comment on function public.admin_export_questions(jsonb) is
  'Sheet rows for the selected questions, including question_id. One question, one row, using its latest complete paper. Skipped questions have no id or no paper that can be written back.';

revoke all on function public.admin_export_questions(jsonb) from public, anon, authenticated;
grant execute on function public.admin_export_questions(jsonb) to authenticated, service_role;
