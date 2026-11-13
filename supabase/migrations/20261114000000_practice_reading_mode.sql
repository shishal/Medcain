-- Reading mode: a practice session the student scrolls, with no attempt.

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
      and rel.relname = 'tests'
      and con.contype = 'c'
      and pg_get_constraintdef(con.oid) ilike '%feedback_timing%'
  loop
    execute format('alter table public.tests drop constraint %I', r.conname);
  end loop;
end $$;

alter table public.tests
  add constraint tests_feedback_timing_check
  check (feedback_timing in ('immediate', 'on_submit', 'reading'));

do $patch$
declare
  v_def text;
  v_old text := $old$  if p_feedback_timing is null
     or p_feedback_timing not in ('immediate', 'on_submit') then
    raise exception 'INVALID_FEEDBACK_TIMING';
  end if;$old$;
  v_new text := $new$  if p_feedback_timing is null
     or p_feedback_timing not in ('immediate', 'on_submit', 'reading') then
    raise exception 'INVALID_FEEDBACK_TIMING';
  end if;$new$;
begin
  v_def := pg_get_functiondef(
    'public.create_practice_session(uuid[], uuid[], public.question_difficulty[], text, int, text, text, int, boolean, uuid[], uuid[])'::regprocedure
  );
  if position(v_old in v_def) = 0 then
    raise exception 'create_practice_session feedback check was not found';
  end if;
  execute replace(v_def, v_old, v_new);
end
$patch$;

do $patch$
declare
  v_def text;
  v_old text := $old$  if v_plan.allow_negative_marking_toggle then
    v_negative_marking := coalesce(p_negative_marking, false);
  else
    v_negative_marking := false;
  end if;$old$;
  v_new text := $new$  if v_plan.allow_negative_marking_toggle then
    v_negative_marking := coalesce(p_negative_marking, false);
  else
    v_negative_marking := false;
  end if;

  -- A scroll of answers is not a timed or scored sitting.
  if p_feedback_timing = 'reading' then
    v_timer_minutes := null;
    v_negative_marking := false;
  end if;$new$;
begin
  v_def := pg_get_functiondef(
    'public.create_practice_session(uuid[], uuid[], public.question_difficulty[], text, int, text, text, int, boolean, uuid[], uuid[])'::regprocedure
  );
  if position(v_old in v_def) = 0 then
    raise exception 'create_practice_session marking block was not found';
  end if;
  execute replace(v_def, v_old, v_new);
end
$patch$;

comment on function public.create_practice_session(
  uuid[], uuid[], public.question_difficulty[], text, int, text, text, int, boolean, uuid[], uuid[]
) is
  'Creates an ephemeral MCQ practice test. feedback_timing may be immediate, on_submit, or reading. Reading forces the timer and negative marking off and does not start an attempt. Clamps to the caller''s plan row and only picks questions plan_allows_question accepts.';
