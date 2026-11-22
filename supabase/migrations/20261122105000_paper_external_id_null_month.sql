-- A Questions sheet uses "-" when a paper has no month. That stores exam_month
-- null. admin_paper_external_id concatenated that null with ||, so the whole
-- id became null and the exam_papers insert failed the not-null constraint.
-- A missing month is an empty piece of the id. A real month still hashes the
-- same way, so existing papers keep their external_id.

create or replace function public.admin_paper_external_id(
  p_university_id uuid,
  p_college_id uuid,
  p_subject_id uuid,
  p_exam_type text,
  p_exam_year int,
  p_exam_month int,
  p_paper_name text
) returns text
language sql
immutable
as $$
  select 'CSV-EP-' || upper(substr(md5(
    p_university_id::text || '|' ||
    coalesce(p_college_id::text, '') || '|' ||
    p_subject_id::text || '|' ||
    coalesce(p_exam_type, '') || '|' ||
    p_exam_year::text || '|' ||
    coalesce(p_exam_month::text, '') || '|' ||
    lower(coalesce(p_paper_name, ''))
  ), 1, 24));
$$;

comment on function public.admin_paper_external_id(uuid, uuid, uuid, text, int, int, text) is
  'Stable exam_papers.external_id. A null month is stored as an empty segment so the id is never null.';

revoke all on function public.admin_paper_external_id(uuid, uuid, uuid, text, int, int, text) from public, anon, authenticated;

-- The import dedupes sittings with the same concatenation. A null month made
-- that key null, so identical "-" rows were not treated as one paper.
do $patch$
declare
  v_def text;
  v_old text := $old$          v_sit_key := v_sitting.university_id::text || '|' ||
            coalesce(v_sitting.college_id::text, '') || '|' ||
            v_sitting.exam_year::text || '|' ||
            v_sitting.exam_month::text || '|' ||
            coalesce(v_sitting.exam_type, '') || '|' ||
            lower(coalesce(v_sitting.paper_name, ''));$old$;
  v_new text := $new$          v_sit_key := v_sitting.university_id::text || '|' ||
            coalesce(v_sitting.college_id::text, '') || '|' ||
            v_sitting.exam_year::text || '|' ||
            coalesce(v_sitting.exam_month::text, '') || '|' ||
            coalesce(v_sitting.exam_type, '') || '|' ||
            lower(coalesce(v_sitting.paper_name, ''));$new$;
begin
  v_def := pg_get_functiondef('public.admin_import_questions(jsonb, jsonb, boolean)'::regprocedure);
  if position(v_old in v_def) = 0 then
    raise exception 'admin_import_questions sitting key was not found';
  end if;
  execute replace(v_def, v_old, v_new);
end
$patch$;
