-- Subject PYQ screens list every university's papers for the subject
-- (own uni / campus / other). Home subject cards used get_study_progress
-- total_pyqs filtered to the student's university only, so the badge was
-- lower than the list. Count distinct active questions on any paper for
-- the subject. Lesson coverage stays university-scoped (progress for the
-- student's own bank).

create or replace function public.get_study_progress()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_phase uuid;
  v_university uuid;
  v_streak int := 0;
  v_cursor date := current_date;
  v_has boolean;
begin
  if v_uid is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  select mbbs_phase_id, university_id
    into v_phase, v_university
  from public.profiles
  where id = v_uid;

  -- Streak: consecutive days with ≥1 event, allowing yesterday if nothing today.
  loop
    select exists (
      select 1 from public.study_events e
      where e.user_id = v_uid
        and e.created_at::date = v_cursor
    ) into v_has;

    if not v_has then
      if v_cursor = current_date then
        v_cursor := v_cursor - 1;
        continue;
      end if;
      exit;
    end if;

    v_streak := v_streak + 1;
    v_cursor := v_cursor - 1;
  end loop;

  return jsonb_build_object(
    'streak', v_streak,
    'days7', coalesce((
      select jsonb_agg(jsonb_build_object('date', d::text, 'count', c) order by d)
      from (
        select gs::date as d, count(e.id) as c
        from generate_series(current_date - 6, current_date, interval '1 day') gs
        left join public.study_events e
          on e.user_id = v_uid and e.created_at::date = gs::date
        group by gs::date
      ) t
    ), '[]'::jsonb),
    'days30', coalesce((
      select jsonb_agg(jsonb_build_object('date', d::text, 'count', c) order by d)
      from (
        select gs::date as d, count(e.id) as c
        from generate_series(current_date - 29, current_date, interval '1 day') gs
        left join public.study_events e
          on e.user_id = v_uid and e.created_at::date = gs::date
        group by gs::date
      ) t
    ), '[]'::jsonb),
    'subjects', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', s.id,
        'name', s.name,
        'learnt_lessons', (
          select count(*) from public.lessons l
          join public.topics tp on tp.id = l.topic_id
          join public.lesson_progress lp
            on lp.lesson_id = l.id and lp.user_id = v_uid and lp.learnt_at is not null
          where tp.subject_id = s.id and l.is_active
            and v_university is not null
            and exists (
              select 1
              from public.questions q
              join public.question_appearances qa on qa.question_id = q.id
              join public.exam_papers ep on ep.id = qa.exam_paper_id
              where q.lesson_id = l.id
                and ep.university_id = v_university
            )
        ),
        'total_lessons', (
          select count(*) from public.lessons l
          join public.topics tp on tp.id = l.topic_id
          where tp.subject_id = s.id and l.is_active
            and v_university is not null
            and exists (
              select 1
              from public.questions q
              join public.question_appearances qa on qa.question_id = q.id
              join public.exam_papers ep on ep.id = qa.exam_paper_id
              where q.lesson_id = l.id
                and ep.university_id = v_university
            )
        ),
        'total_pyqs', (
          select count(distinct q.id)
          from public.questions q
          join public.question_appearances qa on qa.question_id = q.id
          join public.exam_papers ep on ep.id = qa.exam_paper_id
          where ep.subject_id = s.id
            and q.is_active
        )
      ) order by s.display_order)
      from public.subjects s
      where v_phase is null or s.mbbs_phase_id = v_phase
    ), '[]'::jsonb)
  );
end;
$$;
