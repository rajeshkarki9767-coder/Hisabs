-- =============================================================================
-- v89.160: CONTACT-PRIVACY PHASE 2 — party contact meta leaves app_parties
-- =============================================================================
-- WHY
-- Until now every business member's SESSION could read app_parties.meta
-- (phones, emails, DOB, socials, account usernames/tags, notes, referrals)
-- straight from Supabase — the UI hid it (v89.130), the database did not.
-- RLS is row-level and meta was a column on a row every member may read.
--
-- THE FIX
--   1. New table app_party_meta(party_id PK, business_id, meta jsonb):
--      SELECT/INSERT/UPDATE/DELETE only for OWNER or SUPER MANAGER
--      (app5_is_owner_or_sm from v89_140). Realtime + updated_at included
--      (incremental sync cursors work, v89_142 trigger fn reused).
--   2. app_parties gains meta_badges jsonb — a value-free summary (field
--      EXISTS / refused, plus social-platform and account NAMES only) that
--      keeps the v89.102 badges visible to every role.
--   3. A BEFORE INSERT/UPDATE trigger on app_parties REROUTES any meta a
--      client still sends: copies it into app_party_meta, recomputes
--      meta_badges, and NULLs app_parties.meta — so even OLD app builds
--      can never re-leak values into the readable table.
--   4. Backfill: existing meta is copied out, badges computed, column
--      emptied — in one trigger-driven pass.
--
-- DEPLOY ORDER: run this FIRST, then deploy app build 2026.07.11.227+.
-- (Between the two, owners briefly see no contact cards — minutes.)
-- Idempotent; transactional.
-- =============================================================================

BEGIN;

-- 1) Value-free badge summary from a meta blob.
--    {p,pn,e,en,d,dn, s:[{n,x}], a:[{n,x}]} — names only, never values.
CREATE OR REPLACE FUNCTION public.app5_party_badges(m jsonb)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE WHEN m IS NULL THEN NULL ELSE jsonb_strip_nulls(jsonb_build_object(
    'p',  CASE WHEN jsonb_typeof(m->'phones') = 'array' AND jsonb_array_length(m->'phones') > 0 THEN true END,
    'pn', CASE WHEN (m->>'phoneNotShared')::boolean THEN true END,
    'e',  CASE WHEN jsonb_typeof(m->'emails') = 'array' AND jsonb_array_length(m->'emails') > 0 THEN true END,
    'en', CASE WHEN (m->>'emailNotShared')::boolean THEN true END,
    'd',  CASE WHEN COALESCE(m->>'dob','') <> '' THEN true END,
    'dn', CASE WHEN (m->>'dobNotShared')::boolean THEN true END,
    's',  (SELECT jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
             'n', s->>'platform',
             'x', CASE WHEN (s->>'ns')::boolean THEN true END)))
           FROM jsonb_array_elements(CASE WHEN jsonb_typeof(m->'socials')='array' THEN m->'socials' ELSE '[]'::jsonb END) s
           WHERE COALESCE(s->>'platform','') <> ''),
    'a',  (SELECT jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
             'n', d->>'account',
             'x', CASE WHEN (d->>'ns')::boolean THEN true END)))
           FROM jsonb_array_elements(CASE WHEN jsonb_typeof(m->'details')='array' THEN m->'details' ELSE '[]'::jsonb END) d
           WHERE COALESCE(d->>'account','') <> '')
  )) END;
$$;

-- 2) The protected table.
CREATE TABLE IF NOT EXISTS public.app_party_meta (
  party_id    text PRIMARY KEY,
  business_id text NOT NULL,
  meta        jsonb,
  updated_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_party_meta_business   ON public.app_party_meta (business_id);
CREATE INDEX IF NOT EXISTS idx_party_meta_updated_at ON public.app_party_meta (updated_at);
DROP TRIGGER IF EXISTS trg_app5_touch_updated_at ON public.app_party_meta;
CREATE TRIGGER trg_app5_touch_updated_at BEFORE UPDATE ON public.app_party_meta
  FOR EACH ROW EXECUTE FUNCTION public.app5_touch_updated_at();

ALTER TABLE public.app_party_meta ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS app5_party_meta_select ON public.app_party_meta;
CREATE POLICY app5_party_meta_select ON public.app_party_meta
  FOR SELECT USING (public.app5_is_owner_or_sm(business_id));
DROP POLICY IF EXISTS app5_party_meta_insert ON public.app_party_meta;
CREATE POLICY app5_party_meta_insert ON public.app_party_meta
  FOR INSERT WITH CHECK (public.app5_is_owner_or_sm(business_id));
DROP POLICY IF EXISTS app5_party_meta_update ON public.app_party_meta;
CREATE POLICY app5_party_meta_update ON public.app_party_meta
  FOR UPDATE USING (public.app5_is_owner_or_sm(business_id))
             WITH CHECK (public.app5_is_owner_or_sm(business_id));
DROP POLICY IF EXISTS app5_party_meta_delete ON public.app_party_meta;
CREATE POLICY app5_party_meta_delete ON public.app_party_meta
  FOR DELETE USING (public.app5_is_owner_or_sm(business_id));

ALTER TABLE public.app_party_meta REPLICA IDENTITY FULL;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables
                 WHERE pubname='supabase_realtime' AND schemaname='public' AND tablename='app_party_meta') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.app_party_meta;
  END IF;
END $$;

-- 3) Badge column on app_parties (readable by all members, value-free).
ALTER TABLE public.app_parties ADD COLUMN IF NOT EXISTS meta_badges jsonb;

-- 4) Reroute trigger: any meta written to app_parties moves to the
--    protected table; badges recomputed; column forced NULL.
CREATE OR REPLACE FUNCTION public.app5_parties_meta_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.meta IS NOT NULL THEN
    INSERT INTO public.app_party_meta (party_id, business_id, meta)
    VALUES (NEW.id, NEW.business_id, NEW.meta)
    ON CONFLICT (party_id) DO UPDATE
      SET meta = EXCLUDED.meta, business_id = EXCLUDED.business_id, updated_at = now();
    NEW.meta_badges := public.app5_party_badges(NEW.meta);
    NEW.meta := NULL;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_app5_parties_meta_guard ON public.app_parties;
CREATE TRIGGER trg_app5_parties_meta_guard BEFORE INSERT OR UPDATE ON public.app_parties
  FOR EACH ROW EXECUTE FUNCTION public.app5_parties_meta_guard();

-- 5) Backfill + cut in one trigger-driven pass (belt: explicit copy first).
INSERT INTO public.app_party_meta (party_id, business_id, meta)
SELECT id, business_id, meta FROM public.app_parties WHERE meta IS NOT NULL
ON CONFLICT (party_id) DO UPDATE SET meta = EXCLUDED.meta;
UPDATE public.app_parties SET meta = meta WHERE meta IS NOT NULL; -- trigger copies, badges, NULLs

COMMIT;

-- =============================================================================
-- VERIFY — expect: moved = badge_rows, remaining_meta = 0; 4 policies all
-- via app5_is_owner_or_sm; trigger present.
-- =============================================================================
SELECT (SELECT COUNT(*) FROM public.app_party_meta)                                   AS moved,
       (SELECT COUNT(*) FROM public.app_parties WHERE meta_badges IS NOT NULL)        AS badge_rows,
       (SELECT COUNT(*) FROM public.app_parties WHERE meta IS NOT NULL)               AS remaining_meta;
SELECT polname, pg_get_expr(polqual, polrelid) AS using_expr
FROM pg_policy WHERE polrelid = 'public.app_party_meta'::regclass ORDER BY polname;
SELECT tgname FROM pg_trigger WHERE tgrelid = 'public.app_parties'::regclass AND tgname = 'trg_app5_parties_meta_guard';
-- FUNCTIONAL: sign in as a MANAGER/STAFF/VIEWER and run from the app console:
--   (await sb().from('app_party_meta').select('*')).data   → []  (zero rows)
--   (await sb().from('app_parties').select('meta').limit(5)).data → meta all null
--
-- ROLLBACK (restores old behavior; meta stays in app_party_meta — copy back manually if ever needed):
-- BEGIN;
-- DROP TRIGGER IF EXISTS trg_app5_parties_meta_guard ON public.app_parties;
-- DROP FUNCTION IF EXISTS public.app5_parties_meta_guard();
-- COMMIT;
