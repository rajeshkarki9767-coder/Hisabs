-- ============================================================
-- HISABS — Stage 2 SQL
-- ============================================================
-- Adds realtime publication for the per-record tables and a small RLS
-- adjustment so a user who has been invited (but not yet accepted) can
-- still see the name of the business they're invited to. Without this
-- adjustment, the staff invite UI on the invitee's device shows
-- "Unknown business" because RLS hides the business row until
-- membership is accepted.
--
-- Run this in Supabase Dashboard → SQL Editor → New query → Run.
-- Idempotent: safe to re-run.
-- ============================================================

-- ----------------------------------------------------------------
-- Allow pending invitees to read the business name
-- ----------------------------------------------------------------
-- The `can_read_business` helper currently requires status='accepted'.
-- We add a second policy on app_businesses that ALSO permits read when
-- the user has a pending member row matching their email or user_id.
-- Postgres OR-combines multiple policies for the same command, so this
-- widens read access without modifying the helper.

drop policy if exists app_businesses_select_pending on public.app_businesses;
create policy app_businesses_select_pending on public.app_businesses
  for select using (
    exists (
      select 1 from public.app_members m
      where m.business_id = app_businesses.id
        and m.deleted_at is null
        and (
          m.user_id = auth.uid()
          or lower(m.user_login) = lower(coalesce((auth.jwt() ->> 'email'), ''))
        )
    )
  );

-- ----------------------------------------------------------------
-- Realtime publication
-- ----------------------------------------------------------------
-- Add each per-record table to the supabase_realtime publication so the
-- JS client can subscribe to postgres_changes events.
--
-- ALTER PUBLICATION ... ADD TABLE errors if the table is already in the
-- publication. We wrap each in a DO block that swallows the duplicate
-- error so the script stays idempotent.

do $$
declare
  t text;
begin
  for t in select unnest(array[
    'app_accounts',
    'app_businesses',
    'app_books',
    'app_account_groups',
    'app_cash_accounts',
    'app_parties',
    'app_categories',
    'app_members',
    'app_entries',
    'app_audit_expenses'
  ])
  loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception when duplicate_object then
      -- already in the publication; ignore
      null;
    when others then
      raise notice 'Could not add % to publication: %', t, sqlerrm;
    end;
  end loop;
end $$;

-- ============================================================
-- Done. After running this, realtime subscriptions in Hisabs will start
-- delivering events. You can verify in Supabase Dashboard → Database
-- → Replication that all 10 app_* tables show under "Tables".
-- ============================================================
