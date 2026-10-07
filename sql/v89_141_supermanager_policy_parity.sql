-- =============================================================================
-- v89.141: SUPER MANAGER PARITY for role-enumerating policies
-- =============================================================================
-- WHY
-- v89.140's checker query (b) found policies that enumerate role names in
-- their expressions — on your database: app_quick_look_delete / _insert /
-- _update (and this file handles any others the checker matched). A policy
-- written as  role IN ('manager', ...)  predates the Super Manager role, so
-- a supermanager is DENIED writes a manager is allowed. The client (.199)
-- gives supermanager every manager power; the database must agree.
--
-- HOW (no guessing, no hand-copied expressions)
-- For every policy on public.app_% tables whose USING or WITH CHECK text
-- contains the literal 'manager' but NOT 'supermanager', this file:
--   1. prints the policy's CURRENT definition via RAISE NOTICE (your audit
--      trail / manual rollback source),
--   2. recreates the policy IDENTICALLY — same command, same PERMISSIVE/
--      RESTRICTIVE kind, same role grants — with every  'manager'  widened
--      to  'supermanager','manager'  in both expressions.
-- Nothing else about the policy changes. Idempotent: a policy already
-- mentioning 'supermanager' is skipped, so re-running is a no-op.
--
-- SAFETY
--   • Pure widening of an IN-list: a supermanager gains exactly what the
--     manager arm already granted; no other role's access changes.
--   • Transactional; any error rolls everything back.
--   • The NOTICEs printed on first run ARE the rollback: re-create any
--     policy from its printed original if ever needed.
--
-- RUN THIS in the Supabase SQL Editor AFTER v89.140. Then re-run the
-- verification query at the bottom.
-- =============================================================================

BEGIN;

DO $$
DECLARE
  r RECORD;
  v_using  text;
  v_check  text;
  v_roles  text;
  v_cmd    text;
  v_kind   text;
BEGIN
  FOR r IN
    SELECT c.relname                                   AS tbl,
           p.polname                                   AS pol,
           p.polcmd                                    AS cmd,
           p.polpermissive                             AS permissive,
           pg_get_expr(p.polqual,      p.polrelid)     AS using_expr,
           pg_get_expr(p.polwithcheck, p.polrelid)     AS check_expr,
           ARRAY(SELECT rolname FROM pg_roles WHERE oid = ANY (p.polroles)) AS role_names
    FROM pg_policy p
    JOIN pg_class c      ON c.oid = p.polrelid
    JOIN pg_namespace n  ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname LIKE 'app\_%' ESCAPE '\'
      AND (
            (pg_get_expr(p.polqual, p.polrelid)      ILIKE '%''manager''%'
             AND pg_get_expr(p.polqual, p.polrelid)  NOT ILIKE '%supermanager%')
         OR (pg_get_expr(p.polwithcheck, p.polrelid) ILIKE '%''manager''%'
             AND pg_get_expr(p.polwithcheck, p.polrelid) NOT ILIKE '%supermanager%')
      )
  LOOP
    -- 1) Audit trail: the exact policy being replaced.
    RAISE NOTICE 'REWRITING POLICY % ON % | cmd=% permissive=% roles=% | USING: % | WITH CHECK: %',
      r.pol, r.tbl, r.cmd, r.permissive, r.role_names, r.using_expr, r.check_expr;

    -- 2) Widened expressions: 'manager' -> 'supermanager','manager'
    v_using := replace(r.using_expr, '''manager''', '''supermanager'',''manager''');
    v_check := replace(r.check_expr, '''manager''', '''supermanager'',''manager''');
    v_cmd   := CASE r.cmd WHEN 'r' THEN 'SELECT' WHEN 'a' THEN 'INSERT'
                          WHEN 'w' THEN 'UPDATE' WHEN 'd' THEN 'DELETE'
                          ELSE 'ALL' END;
    v_kind  := CASE WHEN r.permissive THEN 'PERMISSIVE' ELSE 'RESTRICTIVE' END;
    v_roles := CASE WHEN r.role_names = '{}' OR r.role_names IS NULL
                    THEN 'public' ELSE array_to_string(r.role_names, ', ') END;

    EXECUTE format('DROP POLICY %I ON public.%I;', r.pol, r.tbl);
    EXECUTE format(
      'CREATE POLICY %I ON public.%I AS %s FOR %s TO %s %s %s;',
      r.pol, r.tbl, v_kind, v_cmd, v_roles,
      CASE WHEN v_using IS NOT NULL THEN format('USING (%s)', v_using) ELSE '' END,
      CASE WHEN v_check IS NOT NULL THEN format('WITH CHECK (%s)', v_check) ELSE '' END
    );
  END LOOP;
END $$;

COMMIT;

-- =============================================================================
-- VERIFY — re-run v89.140's checker. Every remaining match must now ALSO
-- mention supermanager (i.e. this returns 0 rows):
-- =============================================================================
SELECT c.relname, p.polname,
       pg_get_expr(p.polqual, p.polrelid)      AS using_expr,
       pg_get_expr(p.polwithcheck, p.polrelid) AS check_expr
FROM pg_policy p
JOIN pg_class c     ON c.oid = p.polrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relname LIKE 'app\_%' ESCAPE '\'
  AND ( (pg_get_expr(p.polqual, p.polrelid)      ILIKE '%''manager''%'
         AND pg_get_expr(p.polqual, p.polrelid)  NOT ILIKE '%supermanager%')
     OR (pg_get_expr(p.polwithcheck, p.polrelid) ILIKE '%''manager''%'
         AND pg_get_expr(p.polwithcheck, p.polrelid) NOT ILIKE '%supermanager%') );
-- Expect: 0 rows. The Messages tab shows the RAISE NOTICE lines — save them;
-- they are the originals (your rollback source).
--
-- Then one functional test: as a SUPER MANAGER, write a quick-look note
-- (the gated contact quick-look on a party) — it must now save.
