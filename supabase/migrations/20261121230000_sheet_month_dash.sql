-- A Questions sheet may use "-" when the paper has no month. That stores
-- exam_month null. A real month name is unchanged.

create or replace function public.admin_validate_sitting(
  p_university_id uuid,
  p_college_id uuid,
  p_subject_id uuid,
  p_exam_year int,
  p_exam_month int,
  p_exam_type text
) returns void
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if p_subject_id is null or not exists (
    select 1 from public.subjects where id = p_subject_id
  ) then
    raise exception 'Choose a subject that already exists.';
  end if;

  if p_university_id is null or not exists (
    select 1 from public.universities where id = p_university_id
  ) then
    raise exception 'Choose a university that already exists.';
  end if;

  if p_college_id is not null and not exists (
    select 1
    from public.colleges
    where id = p_college_id
      and university_id = p_university_id
  ) then
    raise exception 'That college is not in this university.';
  end if;

  if p_exam_type is null or p_exam_type not in ('prof', 'supply', 'pre_prof', 'internal') then
    raise exception 'Exam type must be prof, supply, pre_prof, or internal.';
  end if;

  if p_exam_year is null or p_exam_year not between 1990 and 2100 then
    raise exception 'Year must be a four-digit year.';
  end if;

  -- Null means the sheet used "-" because the month does not apply.
  if p_exam_month is not null and p_exam_month not between 1 and 12 then
    raise exception 'Month must be 1–12.';
  end if;
end;
$$;

revoke all on function public.admin_validate_sitting(uuid, uuid, uuid, int, int, text) from public, anon, authenticated;

do $patch$
declare
  v_def text;
  v_old text := $old$    v_month_raw := btrim(coalesce(v_row->>'month', ''));
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
    end if;$old$;
  v_new text := $new$    v_month_raw := btrim(coalesce(v_row->>'month', ''));
    if v_month_raw = '' then
      v_month_raw := v_def_month;
    end if;
    -- "-" means this paper has no month. Other text must still be a month name.
    if v_month_raw in ('-', '–', '—', '−') then
      v_month := null;
    elsif v_month_raw = '' then
      v_errors := v_errors || jsonb_build_array('Questions row ' || v_row_no || ': month is required');
    else
      v_month := public.normalize_sheet_exam_month(v_month_raw);
      if v_month is null then
        v_errors := v_errors || jsonb_build_array(
          'Questions row ' || v_row_no || ': month must be a month name such as May or June, or - when there is no month'
        );
      end if;
    end if;$new$;
begin
  v_def := pg_get_functiondef('public.admin_import_questions(jsonb, jsonb, boolean)'::regprocedure);
  if position(v_old in v_def) = 0 then
    raise exception 'admin_import_questions month check was not found';
  end if;
  execute replace(v_def, v_old, v_new);
end
$patch$;

do $patch$
declare
  v_def text;
begin
  v_def := pg_get_functiondef('public.admin_export_questions(jsonb)'::regprocedure);
  if position('coalesce(public.admin_month_name(ep.exam_month::int), '''') as month,' in v_def) = 0 then
    raise exception 'admin_export_questions month column was not found';
  end if;
  v_def := replace(
    v_def,
    'coalesce(public.admin_month_name(ep.exam_month::int), '''') as month,',
    'case when ep.exam_month is null then ''-'' else coalesce(public.admin_month_name(ep.exam_month::int), '''') end as month,'
  );
  if position('and ep.exam_month between 1 and 12' in v_def) = 0 then
    raise exception 'admin_export_questions month filter was not found';
  end if;
  v_def := replace(
    v_def,
    'and ep.exam_month between 1 and 12',
    'and (ep.exam_month is null or ep.exam_month between 1 and 12)'
  );
  v_def := replace(
    v_def,
    'order by qa.question_id, ep.exam_year desc, ep.exam_month desc, ep.id',
    'order by qa.question_id, (ep.exam_month is null), ep.exam_year desc, ep.exam_month desc, ep.id'
  );
  v_def := replace(
    v_def,
    'This question has no paper with a university, year, and month.',
    'This question has no paper with a university and year.'
  );
  execute v_def;
end
$patch$;
