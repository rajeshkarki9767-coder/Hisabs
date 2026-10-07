-- =============================================================================
-- v89.142: updated_at COLUMNS + TRIGGERS — groundwork for incremental sync
-- =============================================================================
-- WHY
-- Every pull currently fetches EVERY row of EVERY table. Incremental sync
-- (client build .207) asks only for "rows changed since my last pull", which
-- needs a server-maintained updated_at on each synced table. This file adds
-- it everywhere, safely.
--
-- WHAT IT DOES, per synced table
--   1. ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now()
--      (Postgres 11+ backfills via the default instantly — no table rewrite)
--   2. BEFORE UPDATE trigger app5_touch_updated_at: every update stamps now().
--      INSERTs are stamped by the column default. Clients never write it.
--   3. Index on (updated_at) so cursor queries ("updated_at > X") are cheap.
--
-- SAFETY / ORDER
--   • 100% client-compatible BOTH ways: the current app (.206) ignores the
--     new column; the next app (.207) requires it. DEPLOY THIS BEFORE .207.
--     (.207 also self-heals: a missing column makes it fall back to a full
--     pull for that table.)
--   • Idempotent: IF NOT EXISTS / OR REPLACE / DROP-then-CREATE throughout.
--   • Transactional.
-- =============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.app5_touch_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'app_businesses', 'app_books', 'app_account_groups', 'app_cash_accounts',
    'app_parties', 'app_categories', 'app_members', 'app_entries',
    'app_audit_expenses', 'app_expense_rates', 'app_quick_look',
    'app_announcements', 'app_transfers',
    'app_distribution_salaries', 'app_distribution_shares', 'app_split_parties'
  ] LOOP
    EXECUTE format(
      'ALTER TABLE public.%I ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();', t);
    EXECUTE format('DROP TRIGGER IF EXISTS trg_app5_touch_updated_at ON public.%I;', t);
    EXECUTE format(
      'CREATE TRIGGER trg_app5_touch_updated_at BEFORE UPDATE ON public.%I
         FOR EACH ROW EXECUTE FUNCTION public.app5_touch_updated_at();', t);
    EXECUTE format(
      'CREATE INDEX IF NOT EXISTS idx_%s_updated_at ON public.%I (updated_at);',
      replace(t, 'app_', ''), t);
  END LOOP;
END $$;

COMMIT;

-- VERIFY — expect 16 rows, each with has_column=true, has_trigger=true:
SELECT c.relname AS table_name,
       EXISTS (SELECT 1 FROM information_schema.columns col
               WHERE col.table_schema='public' AND col.table_name=c.relname
                 AND col.column_name='updated_at')              AS has_column,
       EXISTS (SELECT 1 FROM pg_trigger tg
               WHERE tg.tgrelid=c.oid AND tg.tgname='trg_app5_touch_updated_at') AS has_trigger
FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='public' AND c.relkind='r' AND c.relname = ANY (ARRAY[
  'app_businesses','app_books','app_account_groups','app_cash_accounts',
  'app_parties','app_categories','app_members','app_entries',
  'app_audit_expenses','app_expense_rates','app_quick_look',
  'app_announcements','app_transfers',
  'app_distribution_salaries','app_distribution_shares','app_split_parties'])
ORDER BY 1;
