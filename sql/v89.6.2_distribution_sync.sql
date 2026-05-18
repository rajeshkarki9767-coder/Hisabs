-- ===================================================================
-- Hisabs v89.6.2 — Distribution sync migration (CORRECTED)
-- ===================================================================
-- This version matches the actual schema discovered via diagnostic
-- queries:
--   * IDs are TEXT (not UUID)
--   * Timestamps follow the existing convention: created_at_local
--     (text, client-set), created_at + updated_at + deleted_at
--     (timestamptz, server-managed)
--   * RLS uses the existing user_is_business_member() helper for SELECT
--   * RLS uses owner_id = auth.uid() check for writes (matches the
--     existing pattern on app_businesses)
--
-- Run this in Supabase SQL Editor BEFORE deploying v89.6.2.
-- The migration is wrapped in BEGIN/COMMIT so a single error rolls
-- back everything — your existing data is never touched.
-- ===================================================================

BEGIN;

-- -------------------------------------------------------------------
-- 1. Distribution: Team Salaries
-- -------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.app_distribution_salaries (
    id                  TEXT PRIMARY KEY,
    business_id         TEXT NOT NULL REFERENCES public.app_businesses(id) ON DELETE CASCADE,
    name                TEXT NOT NULL DEFAULT '',
    salary              NUMERIC NOT NULL DEFAULT 0,
    adjustment_type     TEXT NOT NULL DEFAULT 'deduction',
    adjustment_amount   NUMERIC NOT NULL DEFAULT 0,
    note                TEXT NOT NULL DEFAULT '',
    created_at_local    TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at          TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_dist_salaries_business
    ON public.app_distribution_salaries(business_id) WHERE deleted_at IS NULL;

ALTER TABLE public.app_distribution_salaries ENABLE ROW LEVEL SECURITY;

-- Match the existing app_businesses_select pattern using your helper
DROP POLICY IF EXISTS app_distribution_salaries_select ON public.app_distribution_salaries;
CREATE POLICY app_distribution_salaries_select ON public.app_distribution_salaries
    FOR SELECT TO authenticated
    USING (user_is_business_member(business_id));

DROP POLICY IF EXISTS app_distribution_salaries_insert ON public.app_distribution_salaries;
CREATE POLICY app_distribution_salaries_insert ON public.app_distribution_salaries
    FOR INSERT TO authenticated
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.app_businesses b
            WHERE b.id = business_id AND b.owner_id = auth.uid()
        )
    );

DROP POLICY IF EXISTS app_distribution_salaries_update ON public.app_distribution_salaries;
CREATE POLICY app_distribution_salaries_update ON public.app_distribution_salaries
    FOR UPDATE TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.app_businesses b
            WHERE b.id = business_id AND b.owner_id = auth.uid()
        )
    );

DROP POLICY IF EXISTS app_distribution_salaries_delete ON public.app_distribution_salaries;
CREATE POLICY app_distribution_salaries_delete ON public.app_distribution_salaries
    FOR DELETE TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.app_businesses b
            WHERE b.id = business_id AND b.owner_id = auth.uid()
        )
    );

-- -------------------------------------------------------------------
-- 2. Distribution: Profit Shares
-- -------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.app_distribution_shares (
    id                  TEXT PRIMARY KEY,
    business_id         TEXT NOT NULL REFERENCES public.app_businesses(id) ON DELETE CASCADE,
    name                TEXT NOT NULL DEFAULT '',
    pct                 NUMERIC NOT NULL DEFAULT 0,
    note                TEXT NOT NULL DEFAULT '',
    created_at_local    TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at          TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_dist_shares_business
    ON public.app_distribution_shares(business_id) WHERE deleted_at IS NULL;

ALTER TABLE public.app_distribution_shares ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS app_distribution_shares_select ON public.app_distribution_shares;
CREATE POLICY app_distribution_shares_select ON public.app_distribution_shares
    FOR SELECT TO authenticated
    USING (user_is_business_member(business_id));

DROP POLICY IF EXISTS app_distribution_shares_insert ON public.app_distribution_shares;
CREATE POLICY app_distribution_shares_insert ON public.app_distribution_shares
    FOR INSERT TO authenticated
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.app_businesses b
            WHERE b.id = business_id AND b.owner_id = auth.uid()
        )
    );

DROP POLICY IF EXISTS app_distribution_shares_update ON public.app_distribution_shares;
CREATE POLICY app_distribution_shares_update ON public.app_distribution_shares
    FOR UPDATE TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.app_businesses b
            WHERE b.id = business_id AND b.owner_id = auth.uid()
        )
    );

DROP POLICY IF EXISTS app_distribution_shares_delete ON public.app_distribution_shares;
CREATE POLICY app_distribution_shares_delete ON public.app_distribution_shares
    FOR DELETE TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.app_businesses b
            WHERE b.id = business_id AND b.owner_id = auth.uid()
        )
    );

-- -------------------------------------------------------------------
-- 3. Split & Convert: Parties
-- -------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.app_split_parties (
    id                  TEXT PRIMARY KEY,
    business_id         TEXT NOT NULL REFERENCES public.app_businesses(id) ON DELETE CASCADE,
    name                TEXT NOT NULL DEFAULT '',
    pct                 NUMERIC NOT NULL DEFAULT 0,
    is_selected         BOOLEAN NOT NULL DEFAULT FALSE,
    created_at_local    TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at          TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_split_parties_business
    ON public.app_split_parties(business_id) WHERE deleted_at IS NULL;

ALTER TABLE public.app_split_parties ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS app_split_parties_select ON public.app_split_parties;
CREATE POLICY app_split_parties_select ON public.app_split_parties
    FOR SELECT TO authenticated
    USING (user_is_business_member(business_id));

DROP POLICY IF EXISTS app_split_parties_insert ON public.app_split_parties;
CREATE POLICY app_split_parties_insert ON public.app_split_parties
    FOR INSERT TO authenticated
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.app_businesses b
            WHERE b.id = business_id AND b.owner_id = auth.uid()
        )
    );

DROP POLICY IF EXISTS app_split_parties_update ON public.app_split_parties;
CREATE POLICY app_split_parties_update ON public.app_split_parties
    FOR UPDATE TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.app_businesses b
            WHERE b.id = business_id AND b.owner_id = auth.uid()
        )
    );

DROP POLICY IF EXISTS app_split_parties_delete ON public.app_split_parties;
CREATE POLICY app_split_parties_delete ON public.app_split_parties
    FOR DELETE TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.app_businesses b
            WHERE b.id = business_id AND b.owner_id = auth.uid()
        )
    );

-- -------------------------------------------------------------------
-- 4. Realtime publication
-- -------------------------------------------------------------------
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
-- Verification — run these after to confirm
-- ===================================================================
-- 
-- SELECT tablename FROM pg_tables 
-- WHERE tablename IN ('app_distribution_salaries', 'app_distribution_shares', 'app_split_parties');
-- (Should show 3 rows)
--
-- SELECT policyname, cmd FROM pg_policies 
-- WHERE tablename IN ('app_distribution_salaries', 'app_distribution_shares', 'app_split_parties')
-- ORDER BY tablename, cmd;
-- (Should show 12 rows — 4 per table: SELECT, INSERT, UPDATE, DELETE)
--
-- SELECT pubname, tablename FROM pg_publication_tables 
-- WHERE pubname = 'supabase_realtime' 
--   AND tablename IN ('app_distribution_salaries', 'app_distribution_shares', 'app_split_parties');
-- (Should show 3 rows)
--
-- ===================================================================
