-- v89.96: Two new columns on app_businesses
-- 1. vat_order  — controls whether Addition VAT is applied before or after expenses
--                 in the Audit / Distribution / Forecast / Export P&L chain.
--                 Default 'before_expenses' matches existing behaviour.
-- 2. biz_sort_order — user-defined ordering of businesses in the sidebar and
--                     Settings → Profile. NULL = no manual order (falls back to
--                     created_at ordering client-side).
--
-- Run this migration BEFORE deploying the v89.96 app build.
-- Safe to run multiple times (IF NOT EXISTS guards).

ALTER TABLE app_businesses
  ADD COLUMN IF NOT EXISTS vat_order TEXT NOT NULL DEFAULT 'before_expenses',
  ADD COLUMN IF NOT EXISTS biz_sort_order INTEGER;

-- Constraint: only the two valid values are accepted.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'app_businesses_vat_order_check'
      AND table_name = 'app_businesses'
  ) THEN
    ALTER TABLE app_businesses
      ADD CONSTRAINT app_businesses_vat_order_check
      CHECK (vat_order IN ('before_expenses', 'after_expenses'));
  END IF;
END $$;

-- Backfill existing rows (already NULL due to DEFAULT but explicit is safer).
UPDATE app_businesses SET vat_order = 'before_expenses' WHERE vat_order IS NULL;
