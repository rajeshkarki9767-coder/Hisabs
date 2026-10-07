-- =============================================================================
-- v89.140: FIVE-ROLE MODEL AT THE DATABASE (RLS hardening)
-- =============================================================================
-- WHY
-- Builds .179–.206 locked down the UI: owner-only party delete/export, party
-- edits for owner + Super Manager only, rename-own for others, owner-only
-- member-role changes. All of that is JavaScript on the user's device. This
-- migration makes the DATABASE enforce the write-side of the model, so a
-- tampered client with a team member's session can no longer do what the UI
-- already forbids.
--
-- WHAT IT ENFORCES (server-side, per authenticated user):
--   app_parties   DELETE : owner only                      (mirrors v89.121)
--   app_parties   UPDATE : owner | supermanager | creator  (mirrors v89.133;
--                          legacy rows with created_by NULL stay writable by
--                          members — the client already gates those)
--   app_entries   UPDATE : owner | supermanager | manager | creator | legacy-NULL
--   app_entries   DELETE : same  (EXACT mirror of canEditEntry: managers edit
--                          any entry; staff only their own; viewers nothing)
--   app_members   UPDATE : owner any; a member may touch only their OWN or an
--                          UNCLAIMED row and may NOT change the role value
--                          (invite acceptance keeps working; self-promotion
--                          to supermanager/manager is blocked)
--   app_members   DELETE : owner, or yourself (leave business)
--
-- WHAT IT DOES **NOT** DO (known limits, by design):
--   • READ privacy for app_parties.meta (phones, accounts, referrals): RLS is
--     ROW-level; meta is a COLUMN on a row every member may read. Masking it
--     per-role requires moving meta into its own table (app_party_meta) with
--     an owner/supermanager-only SELECT policy + a client change to fetch it.
--     That is PHASE 2 — a coordinated app build, not a SQL-only change.
--   • Period restrictions / export gating: those are read-shaping, same story.
--
-- DESIGN — why every policy here is RESTRICTIVE:
--   Permissive policies OR together; restrictive policies AND with whatever
--   permissive policies already exist. Using AS RESTRICTIVE means this file
--   can only ever NARROW access. It cannot widen anything, it does not need
--   to know your existing policies' names or bodies, and dropping these
--   policies returns you byte-for-byte to today's behavior.
--
-- SUPER MANAGER NOTE
--   Your existing policies are membership-based (app_can_read_business /
--   can_write_business style), not role-enumerating — so a member whose
--   app_members.role = 'supermanager' already reads and writes like any
--   member, and the restrictive policies below grant them the extra write
--   scope. If any OLD policy enumerates role names, the checker query at the
--   bottom will surface it.
--
-- SAFETY
--   • Owner checks go through app_businesses.owner_id = auth.uid() FIRST —
--     the owner can never be locked out by this file.
--   • Helpers are SECURITY DEFINER with pinned search_path (house pattern,
--     same as app_can_read_distribution).
--   • Transactional: any error rolls the whole file back.
--   • Full rollback block at the bottom.
--
-- RUN ORDER
--   1. (optional but smart) Run sql/AUDIT_rls_status.sql — every app_* table
--      should already show rls_enabled + policies. This file assumes that
--      baseline and only tightens it.
--   2. Run THIS file in the Supabase SQL Editor.
--   3. Run the verification queries at the bottom.
--   4. Walk the per-role test checklist (bottom) with real accounts BEFORE
--      trusting it — on test business data, not live books.
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 1) Canonical helpers (namespaced app5_* so nothing existing is touched)
-- -----------------------------------------------------------------------------

-- The caller's role in a business: 'owner' | 'supermanager' | 'manager' |
-- 'staff' | 'viewer' | NULL (not a member). Owner wins even if the owner
-- also has a member row.
CREATE OR REPLACE FUNCTION public.app5_role_for(p_business_id text)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE
    WHEN EXISTS (
      SELECT 1 FROM public.app_businesses b
      WHERE b.id = p_business_id AND b.owner_id = auth.uid()
    ) THEN 'owner'
    ELSE (
      SELECT m.role FROM public.app_members m
      WHERE m.business_id = p_business_id AND m.user_id = auth.uid()
      LIMIT 1
    )
  END;
$$;

CREATE OR REPLACE FUNCTION public.app5_is_owner(p_business_id text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.app_businesses b
    WHERE b.id = p_business_id AND b.owner_id = auth.uid()
  );
$$;

CREATE OR REPLACE FUNCTION public.app5_is_owner_or_sm(p_business_id text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT public.app5_role_for(p_business_id) IN ('owner', 'supermanager');
$$;

-- Manager-and-above (mirrors canEditEntry's blanket arm).
CREATE OR REPLACE FUNCTION public.app5_is_mgr_plus(p_business_id text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT public.app5_role_for(p_business_id) IN ('owner', 'supermanager', 'manager');
$$;

-- Stored role of ONE member row, read as DEFINER so the members policies
-- below can consult it WITHOUT re-entering app_members under RLS — that
-- re-entry is Postgres's classic "infinite recursion detected in policy"
-- failure, and definer functions are the house pattern that avoids it.
CREATE OR REPLACE FUNCTION public.app5_member_role_of(p_member_id text)
RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT m.role FROM public.app_members m WHERE m.id = p_member_id LIMIT 1;
$$;

-- -----------------------------------------------------------------------------
-- 2) app_parties — delete owner-only; edit owner/supermanager/creator
-- -----------------------------------------------------------------------------

DROP POLICY IF EXISTS app5_parties_delete ON public.app_parties;
CREATE POLICY app5_parties_delete ON public.app_parties
  AS RESTRICTIVE FOR DELETE
  USING ( public.app5_is_owner(business_id) );

DROP POLICY IF EXISTS app5_parties_update ON public.app_parties;
CREATE POLICY app5_parties_update ON public.app_parties
  AS RESTRICTIVE FOR UPDATE
  USING (
    public.app5_is_owner_or_sm(business_id)
    OR created_by::text = (auth.uid())::text   -- both-side cast: works for text OR uuid column
    OR created_by IS NULL            -- legacy rows predate created_by stamping
  )
  WITH CHECK (
    public.app5_is_owner_or_sm(business_id)
    OR created_by::text = (auth.uid())::text
    OR created_by IS NULL
  );

-- -----------------------------------------------------------------------------
-- 3) app_entries — edit/delete: owner, or your own entry (legacy NULL allowed)
-- -----------------------------------------------------------------------------

-- EXACT mirror of the client's canEditEntry:
--   owner / supermanager / manager  -> any entry
--   staff                           -> only entries they created
--   viewer / non-member             -> nothing (existing permissive write
--                                      policies already deny; this ANDs)
DROP POLICY IF EXISTS app5_entries_update ON public.app_entries;
CREATE POLICY app5_entries_update ON public.app_entries
  AS RESTRICTIVE FOR UPDATE
  USING (
    public.app5_is_mgr_plus(business_id)
    OR created_by::text = (auth.uid())::text
    OR created_by IS NULL
  )
  WITH CHECK (
    public.app5_is_mgr_plus(business_id)
    OR created_by::text = (auth.uid())::text
    OR created_by IS NULL
  );

DROP POLICY IF EXISTS app5_entries_delete ON public.app_entries;
CREATE POLICY app5_entries_delete ON public.app_entries
  AS RESTRICTIVE FOR DELETE
  USING (
    public.app5_is_mgr_plus(business_id)
    OR created_by::text = (auth.uid())::text
    OR created_by IS NULL
  );

-- -----------------------------------------------------------------------------
-- 4) app_members — the crown jewels: who may change roles
--    • Owner: anything.
--    • A member: may UPDATE only their own row or an unclaimed invite row
--      (user_id IS NULL → acceptance flow), and the resulting row's role
--      must equal the role already stored on that row — so accepting an
--      invite works, but changing your own role to 'supermanager' is
--      rejected by the database.
-- -----------------------------------------------------------------------------

DROP POLICY IF EXISTS app5_members_update ON public.app_members;
CREATE POLICY app5_members_update ON public.app_members
  AS RESTRICTIVE FOR UPDATE
  USING (
    public.app5_is_owner(business_id)
    OR user_id = auth.uid()
    OR user_id IS NULL
  )
  WITH CHECK (
    public.app5_is_owner(business_id)
    -- role must equal the row's stored role (self-escalation blocked);
    -- looked up via a DEFINER helper, never a same-table subquery, so the
    -- policy can NEVER hit "infinite recursion detected in policy".
    OR role = public.app5_member_role_of(id)
  );

DROP POLICY IF EXISTS app5_members_delete ON public.app_members;
CREATE POLICY app5_members_delete ON public.app_members
  AS RESTRICTIVE FOR DELETE
  USING (
    public.app5_is_owner(business_id)
    OR user_id = auth.uid()           -- leaving a business yourself stays allowed
  );

COMMIT;

-- =============================================================================
-- VERIFICATION — run after COMMIT, read the grids
-- =============================================================================

-- (a) The six restrictive policies exist and are RESTRICTIVE:
SELECT polname, relname,
       CASE WHEN polpermissive THEN 'PERMISSIVE (WRONG!)' ELSE 'restrictive ✓' END AS kind
FROM pg_policy p JOIN pg_class c ON c.oid = p.polrelid
WHERE polname LIKE 'app5_%'
ORDER BY relname, polname;
-- Expect 6 rows, all 'restrictive ✓'.

-- (b) No OLD policy enumerates role names (would need a supermanager update):
SELECT c.relname, p.polname, pg_get_expr(p.polqual, p.polrelid) AS using_expr
FROM pg_policy p JOIN pg_class c ON c.oid = p.polrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relname LIKE 'app_%'
  AND (pg_get_expr(p.polqual, p.polrelid) ILIKE '%manager%'
       OR pg_get_expr(p.polwithcheck, p.polrelid) ILIKE '%manager%');
-- Expect 0 rows. Any hit = an old role-enumerating policy; show it to Claude.

-- (c) Helper sanity (run while logged in as the OWNER in the SQL editor's
--     impersonation, or just trust the checklist below):
-- SELECT public.app5_role_for('<your business id>');

-- =============================================================================
-- PER-ROLE TEST CHECKLIST — do this on a TEST business before trusting
-- =============================================================================
-- Deploy nothing; the app is unchanged. Test with real logged-in accounts:
--   OWNER         : edit any party ✓ · delete a party ✓ · change a role ✓
--   SUPER MANAGER : edit any party ✓ · delete a party ✗(fails) ·
--                   edit teammate's entry ✓ (managers edit any entry)
--   MANAGER       : rename own-created party ✓ · edit other's party ✗ ·
--                   edit teammate's entry ✓ · delete any party ✗ ·
--                   change own role ✗
--   STAFF         : edit own entry ✓ · edit teammate's entry ✗ · delete party ✗
--   VIEWER        : any write ✗ (your existing write policies already deny;
--                   these only tighten further)
--   INVITE FLOW   : invite a fresh account at any role → accept → must work.
-- A blocked write surfaces in-app as a sync error on that row — expected for
-- the ✗ cases, a bug report for the ✓ cases.
--
-- =============================================================================
-- ROLLBACK — restores today's exact behavior
-- =============================================================================
-- BEGIN;
-- DROP POLICY IF EXISTS app5_parties_delete  ON public.app_parties;
-- DROP POLICY IF EXISTS app5_parties_update  ON public.app_parties;
-- DROP POLICY IF EXISTS app5_entries_update  ON public.app_entries;
-- DROP POLICY IF EXISTS app5_entries_delete  ON public.app_entries;
-- DROP POLICY IF EXISTS app5_members_update  ON public.app_members;
-- DROP POLICY IF EXISTS app5_members_delete  ON public.app_members;
-- DROP FUNCTION IF EXISTS public.app5_member_role_of(text);
-- DROP FUNCTION IF EXISTS public.app5_is_mgr_plus(text);
-- DROP FUNCTION IF EXISTS public.app5_is_owner_or_sm(text);
-- DROP FUNCTION IF EXISTS public.app5_is_owner(text);
-- DROP FUNCTION IF EXISTS public.app5_role_for(text);
-- COMMIT;
