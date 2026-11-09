-- The website admin is the question editor. Saves no longer queue a sheet
-- pull, and a leftover Sync to App cannot delete questions missing from a
-- snapshot.

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
begin
  -- Kept so existing save functions still call it. It records nothing.
  return;
end;
$$;

revoke all on function public.admin_enqueue_sheet(uuid, uuid, text, jsonb) from public, anon, authenticated;

drop function if exists public.admin_sheet_row(uuid, uuid);
drop function if exists public.export_sheet_outbox();
drop function if exists public.ack_sheet_outbox(uuid[]);
drop table if exists public.sheet_outbox;

create or replace function public.sync_content_csv(
  p_rows jsonb,
  p_apply boolean default false
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  raise exception 'The question sheet is retired. Edit questions in the website admin.';
end;
$$;

comment on function public.sync_content_csv(jsonb, boolean) is
  'Retired. A sheet Apply must not insert, update, or delete questions.';

revoke all on function public.sync_content_csv(jsonb, boolean) from public, anon, authenticated, service_role;
