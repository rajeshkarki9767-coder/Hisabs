-- ===================================================================
-- Hisabs v89.8 — POST-DEPLOY DIAGNOSTIC QUERIES
-- ===================================================================
-- Run these in Supabase SQL Editor AFTER deploying v89.8.
-- They tell you whether sync is actually working, and if not, why.
--
-- Run them in order. The comments above each query explain what
-- "good" looks like and what action to take if it's not.
-- ===================================================================


-- ===================================================================
-- QUERY 1 — Who does Supabase think owns each business?
-- ===================================================================
-- WHAT TO LOOK FOR:
--   The `owner_id` column should match the `auth.uid()` of whoever
--   you EXPECT to be the owner. If you renamed "Steve" to "Zeus" in
--   the display name but the underlying auth account didn't change,
--   the owner_id will still be Steve's original uid.
--
-- If owner_id is wrong, see "FIX OWNERSHIP" below.
-- ===================================================================
SELECT
    b.id                                          AS business_id,
    b.name                                        AS business_name,
    b.owner_id                                    AS db_owner_uid,
    u.email                                       AS db_owner_email,
    u.raw_user_meta_data->>'display_name'         AS db_owner_display_name,
    b.created_at
FROM public.app_businesses b
LEFT JOIN auth.users u ON u.id = b.owner_id
WHERE b.deleted_at IS NULL
ORDER BY b.created_at;


-- ===================================================================
-- QUERY 2 — What does Supabase think YOU are right now?
-- ===================================================================
-- Run this from the Supabase SQL Editor while logged in as the user
-- you're testing on the phone. It returns the auth.uid() that
-- queries from your phone will use to evaluate RLS.
--
-- Compare the result here against `db_owner_uid` from Query 1:
--   * If they match  → you ARE the owner; writes should work
--   * If they differ → you're NOT the owner; RLS will reject writes
-- ===================================================================
SELECT
    auth.uid()                                    AS my_uid,
    auth.email()                                  AS my_email;


-- ===================================================================
-- QUERY 3 — All members across all businesses
-- ===================================================================
-- WHAT TO LOOK FOR:
--   For each business you care about, who has access? The `role`
--   column is informational only — RLS uses `app_businesses.owner_id`
--   for write permission, NOT `app_members.role`. So even if Zeus
--   is listed in app_members with role='owner', writes will only
--   succeed if `app_businesses.owner_id = Zeus's auth.uid()`.
-- ===================================================================
SELECT
    b.name                                        AS business_name,
    m.user_id                                     AS member_uid,
    u.email                                       AS member_email,
    u.raw_user_meta_data->>'display_name'         AS member_display,
    m.role                                        AS role,
    m.status                                      AS status
FROM public.app_members m
LEFT JOIN public.app_businesses b ON b.id = m.business_id
LEFT JOIN auth.users u ON u.id = m.user_id
WHERE m.deleted_at IS NULL
ORDER BY b.name, m.role DESC;


-- ===================================================================
-- QUERY 4 — Did v89.8 successfully write any distribution data yet?
-- ===================================================================
-- WHAT TO LOOK FOR:
--   * Counts > 0 → at least one write reached the server. Sync IS
--     working for this user. If your yellow dot still shows, it's
--     about something else (or stuck old ops).
--   * All counts 0 → no writes reaching Supabase. Likely cause:
--     - You're not the database owner (see Query 1 vs Query 2)
--     - Or sync hasn't drained yet (wait 30s, check again)
-- ===================================================================
SELECT 'app_distribution_salaries' AS table_name, COUNT(*) AS rows FROM public.app_distribution_salaries
UNION ALL
SELECT 'app_distribution_shares',              COUNT(*) FROM public.app_distribution_shares
UNION ALL
SELECT 'app_split_parties',                    COUNT(*) FROM public.app_split_parties;


-- ===================================================================
-- QUERY 5 — Verify v89.6.2 SQL migration is intact
-- ===================================================================
-- This confirms the SQL migration you ran earlier is still healthy.
-- Should show:
--   * 3 tables (the new ones)
--   * 12 policies (4 per table: SELECT, INSERT, UPDATE, DELETE)
--   * 3 publication entries
-- ===================================================================

-- 5a. Tables present
SELECT tablename
FROM pg_tables
WHERE tablename IN ('app_distribution_salaries', 'app_distribution_shares', 'app_split_parties');

-- 5b. Policies present
SELECT tablename, policyname, cmd
FROM pg_policies
WHERE tablename IN ('app_distribution_salaries', 'app_distribution_shares', 'app_split_parties')
ORDER BY tablename, cmd;

-- 5c. Realtime publication
SELECT tablename
FROM pg_publication_tables
WHERE pubname = 'supabase_realtime'
  AND tablename IN ('app_distribution_salaries', 'app_distribution_shares', 'app_split_parties');


-- ===================================================================
-- IF QUERY 1 SHOWS THE WRONG OWNER — FIX OWNERSHIP
-- ===================================================================
-- Scenario: You renamed the display name from "Steve" to "Zeus" but
-- the underlying account changed too (or you're now logging in as
-- a different user). The business's owner_id is still pointing at
-- the OLD account.
--
-- DON'T just blindly UPDATE. Make sure you know what you're doing:
--
--   1. From Query 2, get your current auth.uid (let's call it NEW_UID).
--   2. From Query 1, get the business's current owner_id (OLD_UID).
--   3. Confirm you actually want to transfer ownership from OLD_UID
--      to NEW_UID. THIS CANNOT BE UNDONE without manual SQL.
--   4. Run the UPDATE below, replacing NEW_UID and OLD_UID with the
--      actual UUIDs from Query 1 and Query 2.
--
-- Example (DO NOT RUN AS-IS — replace UUIDs):
--
--   UPDATE public.app_businesses
--   SET owner_id = 'NEW_UID_HERE'::uuid,
--       updated_at = NOW()
--   WHERE owner_id = 'OLD_UID_HERE'::uuid;
--
-- After the UPDATE, refresh your app and the yellow sync dot should
-- start to clear within ~30s (any new distribution writes you make
-- will now pass RLS).
--
-- IMPORTANT: This only fixes ownership in app_businesses. If you
-- want the OLD owner to retain access as a manager, you need to
-- INSERT them into app_members with role='manager' separately.
-- ===================================================================


-- ===================================================================
-- IF SYNC STILL FAILS AFTER OWNERSHIP IS CORRECT — DEBUG INDIVIDUAL OPS
-- ===================================================================
-- The v89.8 stuck-op purge runs ONCE on first boot. If you trigger
-- another failure after that (e.g. by making a distribution edit on
-- a still-wrong-owner device), it can refill the queue.
--
-- To manually purge ALL distribution-related queue entries from a
-- specific device, run this in the browser console (DevTools):
--
--   localStorage.removeItem('hisabs_v898_dist_purge_done');
--   location.reload();
--
-- This forces the v89.8 purge to run again on next boot.
-- ===================================================================


-- ===================================================================
-- TROUBLESHOOTING DECISION TREE
-- ===================================================================
--
-- 1. Run Query 4. Are there any rows in the new tables?
--    NO  → Sync isn't writing. Go to step 2.
--    YES → Sync IS writing. Yellow dot is probably stale. Try the
--          localStorage purge above and reload.
--
-- 2. Run Query 1. What does owner_id show for your business?
--    Then run Query 2 from the user's session. Do they match?
--    YES → Should work. Check Query 5 to confirm policies are intact.
--    NO  → You're not the owner per the database. Either:
--          (a) UPDATE the owner_id (see "FIX OWNERSHIP" above)
--          (b) Log in as the actual owner
--
-- 3. Still failing? Open the browser console on the failing device
--    and screenshot the actual error message. Paste it back to me.
-- ===================================================================
