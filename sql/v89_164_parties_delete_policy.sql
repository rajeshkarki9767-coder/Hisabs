-- =============================================================================
-- v89.164: FIX — deleted parties reappear after refresh
-- =============================================================================
-- ROOT CAUSE
-- A DELETE blocked by row-level security does NOT error — it just deletes
-- 0 rows and reports success. app_parties has v89_140's RESTRICTIVE
-- owner-only delete policy, but a restrictive policy can only NARROW what
-- a PERMISSIVE policy grants — and app_parties has no permissive DELETE
-- policy granting anything to narrow. Net effect: every parties delete
-- silently removes 0 rows, the app's sync queue marks the op as synced,
-- the cloud row survives, and the next pull restores the party locally.
--
-- FIX
-- Add the missing PERMISSIVE base policy: any business member may reach
-- the delete statement. The RESTRICTIVE app5_parties_delete still ANDs on
-- top, so the final rule is unchanged from the design: OWNER ONLY can
-- delete parties. No other role gains anything.
--
-- Also recreates app5_is_owner with both-side text casts (same hardening
-- the v89_140 update policy already used) — harmless if owner_id is uuid,
-- and future-proof if it is text.
--
-- RUN THIS in the Supabase SQL Editor. Idempotent. Then delete a party in
-- the app and refresh — it must stay gone.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.app5_is_owner(p_business_id text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.app_businesses b
    WHERE b.id = p_business_id AND b.owner_id::text = (auth.uid())::text
  );
$$;

DROP POLICY IF EXISTS app_parties_delete_base ON public.app_parties;
CREATE POLICY app_parties_delete_base ON public.app_parties
  AS PERMISSIVE FOR DELETE
  USING ( public.app5_role_for(business_id) IS NOT NULL );

-- =============================================================================
-- VERIFY 1 — every policy now on app_parties (paste this back if deletes
-- still misbehave). Expect to see app_parties_delete_base (permissive, d)
-- AND app5_parties_delete (restrictive, d) among them:
-- =============================================================================
SELECT p.polname,
       CASE WHEN p.polpermissive THEN 'PERMISSIVE' ELSE 'RESTRICTIVE' END AS kind,
       CASE p.polcmd WHEN 'r' THEN 'SELECT' WHEN 'a' THEN 'INSERT'
                     WHEN 'w' THEN 'UPDATE' WHEN 'd' THEN 'DELETE' ELSE 'ALL' END AS cmd,
       pg_get_expr(p.polqual, p.polrelid) AS using_expr
FROM pg_policy p
JOIN pg_class c ON c.oid = p.polrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relname = 'app_parties'
ORDER BY p.polcmd, p.polname;
