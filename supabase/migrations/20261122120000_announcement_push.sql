-- One lock-screen alert the first time an announcement becomes active.
-- The inbox row is still the record. A failed send leaves push_sent_at null
-- so turning Publish off and on again retries. Editing a row that is already
-- published does not send again.
--
-- The Flutter admin screen, the website admin, and the Table Editor all write
-- this table. The trigger is the shared moment, so none of them call FCM.
--
-- Queuing needs two Vault secrets (SQL editor) and the matching Edge Function
-- secret. Until those exist, publish still saves the inbox row and skips the
-- alert:
--   select vault.create_secret(
--     'https://<project-ref>.supabase.co/functions/v1/send-announcement-push',
--     'push_function_url'
--   );
--   select vault.create_secret('<PUSH_WEBHOOK_SECRET>', 'push_function_secret');

alter table public.announcements
  add column if not exists push_sent_at timestamptz;

comment on column public.announcements.push_sent_at is
  'Set when the one broadcast is claimed. Cleared if FCM does not accept it. Null means it can still be sent.';

create extension if not exists pg_net;

create or replace function private.enqueue_announcement_push(p_announcement_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_url text;
  v_secret text;
begin
  begin
    select ds.decrypted_secret
      into v_url
    from vault.decrypted_secrets ds
    where ds.name = 'push_function_url'
    limit 1;

    select ds.decrypted_secret
      into v_secret
    from vault.decrypted_secrets ds
    where ds.name = 'push_function_secret'
    limit 1;
  exception
    when undefined_table or invalid_schema_name then
      return;
  end;

  if v_url is null or btrim(v_url) = ''
     or v_secret is null or btrim(v_secret) = '' then
    return;
  end if;

  -- Inserts a row in the pg_net queue. The HTTP call runs after commit.
  perform net.http_post(
    url := v_url,
    body := jsonb_build_object('announcement_id', p_announcement_id),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_secret
    )
  );
exception
  when undefined_function then
    raise warning 'announcement push skipped: pg_net is not installed';
end;
$$;

revoke all on function private.enqueue_announcement_push(uuid) from public, anon, authenticated;

create or replace function private.announcements_push_on_publish()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    if new.is_active and new.push_sent_at is null then
      begin
        perform private.enqueue_announcement_push(new.id);
      exception
        when others then
          raise warning 'announcement push was not queued: %', sqlerrm;
      end;
    end if;
    return new;
  end if;

  -- Already-published edits set is_active again. Only a real off-to-on
  -- change alerts, and only when the previous attempt never succeeded.
  if new.is_active and not old.is_active and new.push_sent_at is null then
    begin
      perform private.enqueue_announcement_push(new.id);
    exception
      when others then
        raise warning 'announcement push was not queued: %', sqlerrm;
    end;
  end if;
  return new;
end;
$$;

revoke all on function private.announcements_push_on_publish() from public, anon, authenticated;

drop trigger if exists announcements_push_on_publish on public.announcements;

create trigger announcements_push_on_publish
  after insert or update on public.announcements
  for each row
  execute function private.announcements_push_on_publish();
