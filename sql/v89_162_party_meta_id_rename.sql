-- =============================================================================
-- v89.162: HOTFIX — app_party_meta key column renamed party_id → id
-- =============================================================================
-- WHY (the "syncing pending" bug after v89_160)
-- The app's sync engine assumes every synced table's key column is `id`:
--   • queue drain:  .upsert(rows, { onConflict: 'id' })   and   .delete().in('id', ...)
--   • full pulls:   .order('id', { ascending: true })
-- v89_160 created app_party_meta with `party_id` as the key, so every pull
-- and push against it failed (42703: column app_party_meta.id does not
-- exist) and the queue showed "pending" forever. Renaming the column to
-- `id` fixes pull, push, and delete in one stroke. The PK, index and RLS
-- policies follow the rename automatically (policies key on business_id).
-- No data is touched. Run this, then let devices update to build .229+.
-- Idempotent: skips the rename if already done.
-- =============================================================================

BEGIN;

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema='public' AND table_name='app_party_meta' AND column_name='party_id') THEN
    ALTER TABLE public.app_party_meta RENAME COLUMN party_id TO id;
  END IF;
END $$;

-- Reroute trigger fn must reference the new column name.
CREATE OR REPLACE FUNCTION public.app5_parties_meta_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.meta IS NOT NULL THEN
    INSERT INTO public.app_party_meta (id, business_id, meta)
    VALUES (NEW.id, NEW.business_id, NEW.meta)
    ON CONFLICT (id) DO UPDATE
      SET meta = EXCLUDED.meta, business_id = EXCLUDED.business_id, updated_at = now();
    NEW.meta_badges := public.app5_party_badges(NEW.meta);
    NEW.meta := NULL;
  END IF;
  RETURN NEW;
END;
$$;

COMMIT;

-- VERIFY — expect columns: id, business_id, meta, updated_at; count unchanged (137):
SELECT column_name FROM information_schema.columns
WHERE table_schema='public' AND table_name='app_party_meta' ORDER BY ordinal_position;
SELECT COUNT(*) AS rows_still_there FROM public.app_party_meta;
