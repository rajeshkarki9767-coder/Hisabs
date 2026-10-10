-- =============================================================================
-- v89.163: ADJUSTMENT FLAG on parties and categories
-- =============================================================================
-- WHY
-- Discrepancies between the Discord first-entry and the Hisabs entry are
-- corrected with entries against a dedicated "Adjustment" party/category
-- into the real account, so account totals match reality. The flag marks
-- those records so the client can badge them (ADJ) everywhere, instead of
-- them looking like ordinary trade.
--
-- WHAT
-- One nullable boolean column on each table. NULL/false = normal record
-- (every existing row), true = adjustment record. No RLS change needed:
-- the columns ride the existing parties/categories policies.
--
-- RUN THIS in the Supabase SQL Editor BEFORE opening the 2026.07.11.231
-- build. The new build always sends `adj` on party/category pushes, so the
-- column must exist first (otherwise those pushes fail with 42703 until
-- this runs — the queue retries, nothing is lost, but sync stalls).
-- Idempotent: re-running is a no-op.
-- =============================================================================

ALTER TABLE public.app_parties    ADD COLUMN IF NOT EXISTS adj boolean;
ALTER TABLE public.app_categories ADD COLUMN IF NOT EXISTS adj boolean;

-- VERIFY — expect 2 rows, one per table:
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN ('app_parties', 'app_categories')
  AND column_name = 'adj'
ORDER BY table_name;
