-- ===================================================================
-- Hisabs v89.6 — Distribution sync migration
-- ===================================================================
-- Run this in Supabase SQL Editor BEFORE deploying the v89.6 client.
-- The client gracefully falls back to localStorage if these tables
-- don't exist, but managers won't see owner changes until they do.
--
-- Three new tables, all keyed by business_id:
--   app_distribution_salaries   — Team Salaries section rows
--   app_distribution_shares     — Profit Shares section rows
--   app_split_parties           — Split & convert parties (Net Profit split)
--
-- Also adds two columns to app_businesses for the per-business
-- single-currency settings (currency code + rate). These were
-- formerly localStorage-only.
--
-- RLS:
--   - Members of a business can SELECT (read) any of its rows
--   - ONLY the business owner can INSERT/UPDATE/DELETE
--   - Realtime publication enabled so manager sees changes live
-- ===================================================================

BEGIN;

-- -------------------------------------------------------------------
-- 1. Distribution: Team Salaries
-- -------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.app_distribution_salaries (
    id                  UUID PRIMARY KEY,
    business_id         UUID NOT NULL REFERENCES public.app_businesses(id) ON DELETE CASCADE,
    name                TEXT NOT NULL DEFAULT '',
    salary              NUMERIC(14,2) NOT NULL DEFAULT 0,
    adjustment_type     TEXT NOT NULL DEFAULT 'deduction',
    adjustment_amount   NUMERIC(14,2) NOT NULL DEFAULT 0,
    note                TEXT NOT NULL DEFAULT '',
    sort_order          INT,
    created_at_local    TIMESTAMPTZ,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at          TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_dist_salaries_business
    ON public.app_distribution_salaries(business_id) WHERE deleted_at IS NULL;

ALTER TABLE public.app_distribution_salaries ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS dist_salaries_select ON public.app_distribution_salaries;
CREATE POLICY dist_salaries_select ON public.app_distribution_salaries
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.app_businesses b
            WHERE b.id = business_id
              AND (b.owner_id = auth.uid()
                   OR EXISTS (
                       SELECT 1 FROM public.app_members m
                       WHERE m.business_id = b.id
                         AND m.user_id = auth.uid()
                         AND m.status NOT IN ('revoked', 'removed', 'declined')
                   )
              )
        )
    );

DROP POLICY IF EXISTS dist_salaries_write ON public.app_distribution_salaries;
CREATE POLICY dist_salaries_write ON public.app_distribution_salaries
    FOR ALL TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.app_businesses b
            WHERE b.id = business_id AND b.owner_id = auth.uid()
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.app_businesses b
            WHERE b.id = business_id AND b.owner_id = auth.uid()
        )
    );

-- -------------------------------------------------------------------
-- 2. Distribution: Profit Shares
-- -------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.app_distribution_shares (
    id                  UUID PRIMARY KEY,
    business_id         UUID NOT NULL REFERENCES public.app_businesses(id) ON DELETE CASCADE,
    name                TEXT NOT NULL DEFAULT '',
    pct                 NUMERIC(7,4) NOT NULL DEFAULT 0,
    note                TEXT NOT NULL DEFAULT '',
    sort_order          INT,
    created_at_local    TIMESTAMPTZ,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at          TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_dist_shares_business
    ON public.app_distribution_shares(business_id) WHERE deleted_at IS NULL;

ALTER TABLE public.app_distribution_shares ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS dist_shares_select ON public.app_distribution_shares;
CREATE POLICY dist_shares_select ON public.app_distribution_shares
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.app_businesses b
            WHERE b.id = business_id
              AND (b.owner_id = auth.uid()
                   OR EXISTS (
                       SELECT 1 FROM public.app_members m
                       WHERE m.business_id = b.id
                         AND m.user_id = auth.uid()
                         AND m.status NOT IN ('revoked', 'removed', 'declined')
                   )
              )
        )
    );

DROP POLICY IF EXISTS dist_shares_write ON public.app_distribution_shares;
CREATE POLICY dist_shares_write ON public.app_distribution_shares
    FOR ALL TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.app_businesses b
            WHERE b.id = business_id AND b.owner_id = auth.uid()
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.app_businesses b
            WHERE b.id = business_id AND b.owner_id = auth.uid()
        )
    );

-- -------------------------------------------------------------------
-- 3. Split & Convert: Parties
-- -------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.app_split_parties (
    id                  UUID PRIMARY KEY,
    business_id         UUID NOT NULL REFERENCES public.app_businesses(id) ON DELETE CASCADE,
    name                TEXT NOT NULL DEFAULT '',
    pct                 NUMERIC(7,4) NOT NULL DEFAULT 0,
    is_selected         BOOLEAN NOT NULL DEFAULT FALSE,
    sort_order          INT,
    created_at_local    TIMESTAMPTZ,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at          TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_split_parties_business
    ON public.app_split_parties(business_id) WHERE deleted_at IS NULL;

ALTER TABLE public.app_split_parties ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS split_parties_select ON public.app_split_parties;
CREATE POLICY split_parties_select ON public.app_split_parties
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.app_businesses b
            WHERE b.id = business_id
              AND (b.owner_id = auth.uid()
                   OR EXISTS (
                       SELECT 1 FROM public.app_members m
                       WHERE m.business_id = b.id
                         AND m.user_id = auth.uid()
                         AND m.status NOT IN ('revoked', 'removed', 'declined')
                   )
              )
        )
    );

DROP POLICY IF EXISTS split_parties_write ON public.app_split_parties;
CREATE POLICY split_parties_write ON public.app_split_parties
    FOR ALL TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.app_businesses b
            WHERE b.id = business_id AND b.owner_id = auth.uid()
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.app_businesses b
            WHERE b.id = business_id AND b.owner_id = auth.uid()
        )
    );

-- -------------------------------------------------------------------
-- 4. Additional split settings on app_businesses
--    (single-% legacy mode, currency, rate, selected party)
-- -------------------------------------------------------------------
ALTER TABLE public.app_businesses
    ADD COLUMN IF NOT EXISTS split_pct         NUMERIC(7,4) NOT NULL DEFAULT 100,
    ADD COLUMN IF NOT EXISTS split_currency    TEXT NOT NULL DEFAULT '',
    ADD COLUMN IF NOT EXISTS split_rate        NUMERIC(18,8) NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS split_selected_party_id UUID;

-- -------------------------------------------------------------------
-- 5. Realtime publication
-- -------------------------------------------------------------------
-- Add new tables to the supabase_realtime publication so the client's
-- existing subscription picks them up. Idempotent; safe to re-run.
DO $$
BEGIN
    BEGIN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.app_distribution_salaries;
    EXCEPTION WHEN duplicate_object THEN NULL;
    END;
    BEGIN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.app_distribution_shares;
    EXCEPTION WHEN duplicate_object THEN NULL;
    END;
    BEGIN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.app_split_parties;
    EXCEPTION WHEN duplicate_object THEN NULL;
    END;
END $$;

COMMIT;

-- ===================================================================
-- Verification queries — run these after the migration to confirm:
-- ===================================================================
--
-- SELECT tablename FROM pg_tables WHERE tablename LIKE 'app_distribution_%' OR tablename LIKE 'app_split_%';
--   (Should show 3 rows)
--
-- SELECT column_name FROM information_schema.columns
--   WHERE table_name = 'app_businesses' AND column_name LIKE 'split_%';
--   (Should show split_pct, split_currency, split_rate, split_selected_party_id)
--
-- SELECT policyname FROM pg_policies WHERE tablename IN
--   ('app_distribution_salaries', 'app_distribution_shares', 'app_split_parties');
--   (Should show 6 rows — 2 per table)
--
-- ===================================================================
-- After running this migration, deploy the v89.6 client. The client
-- will automatically migrate localStorage data to these tables on
-- next boot.
-- ===================================================================
