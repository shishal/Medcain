-- admin_ensure_topic_lesson returns a column named topic_id. The lesson
-- insert then reads lessons.topic_id. Postgres treats both as the same
-- name and raises "column reference topic_id is ambiguous" while saving
-- a question that has a topic. Qualify the table column.

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
#variable_conflict use_column
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
    and lower(btrim(t.name)) = lower(v_chapter)
  order by t.id
  limit 1;

  if v_topic_id is null then
    insert into public.topics (subject_id, name, display_order)
    values (
      p_subject_id,
      v_chapter,
      (
        select coalesce(max(t.display_order), 0) + 1
        from public.topics t
        where t.subject_id = p_subject_id
      )
    )
    returning id into v_topic_id;
  end if;

  if v_topic is not null then
    select l.id into v_lesson_id
    from public.lessons l
    where l.topic_id = v_topic_id
      and lower(btrim(l.name)) = lower(v_topic)
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
          select coalesce(max(l.display_order), 0) + 1
          from public.lessons l
          where l.topic_id = v_topic_id
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

comment on function public.admin_ensure_topic_lesson(uuid, text, text, public.plan_tier, boolean) is
  'Finds or creates the chapter and topic for an admin question save. lessons.topic_id is qualified because this function also returns a column named topic_id.';

revoke all on function public.admin_ensure_topic_lesson(uuid, text, text, public.plan_tier, boolean) from public, anon, authenticated;
