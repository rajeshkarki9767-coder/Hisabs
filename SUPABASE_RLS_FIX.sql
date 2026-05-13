-- ============================================================
-- HISABS — RLS Fix (missing INSERT policies)
-- ============================================================
-- Diagnostic against the live project showed that only 3 of the 10
-- app_* tables had INSERT policies (app_accounts, app_businesses,
-- app_members). Postgres treats RLS-enabled tables with no policy
-- for an operation as deny-by-default — every INSERT to the other
-- 7 tables was being rejected with 42501.
--
-- This script:
--   1. Verifies the can_write_business() helper exists (Stage 1 should
--      have created it; if not, recreates it).
--   2. Drops any existing INSERT policy on each of the 7 tables (so
--      this script is idempotent — safe to re-run).
--   3. Creates the correct INSERT policy on each.
--
-- It does NOT touch existing SELECT/UPDATE/DELETE policies.
-- It does NOT touch data.
-- It does NOT change RLS enabled state.
--
-- Run this once in Supabase Dashboard → SQL Editor → New query.
-- ============================================================

-- ----------------------------------------------------------------
-- 1. Ensure helper functions exist
-- ----------------------------------------------------------------
-- can_write_business: returns true if the caller is owner of the
-- business, or an accepted member with a non-viewer role. Used by
-- INSERT/UPDATE policies on every child table.

create or replace function public.can_write_business(bid text)
returns boolean language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.app_businesses b
    where b.id = bid and b.owner_id = auth.uid()
  ) or exists (
    select 1 from public.app_members m
    where m.business_id = bid
      and m.user_id = auth.uid()
      and m.status = 'accepted'
      and coalesce(m.role, '') in ('manager', 'staff')
  );
$$;

-- ----------------------------------------------------------------
-- 2. Re-create INSERT policies on the 7 child tables
-- ----------------------------------------------------------------
-- Pattern is the same for every one: the row's business_id must be
-- writable by the caller, per can_write_business().

drop policy if exists app_books_insert on public.app_books;
create policy app_books_insert on public.app_books
  for insert with check (public.can_write_business(business_id));

drop policy if exists app_account_groups_insert on public.app_account_groups;
create policy app_account_groups_insert on public.app_account_groups
  for insert with check (public.can_write_business(business_id));

drop policy if exists app_cash_accounts_insert on public.app_cash_accounts;
create policy app_cash_accounts_insert on public.app_cash_accounts
  for insert with check (public.can_write_business(business_id));

drop policy if exists app_parties_insert on public.app_parties;
create policy app_parties_insert on public.app_parties
  for insert with check (public.can_write_business(business_id));

drop policy if exists app_categories_insert on public.app_categories;
create policy app_categories_insert on public.app_categories
  for insert with check (public.can_write_business(business_id));

-- Entries are special: they reference book_id, but the RLS check
-- needs business_id, which is denormalised onto the row at push time
-- by the client. We check business_id directly.
drop policy if exists app_entries_insert on public.app_entries;
create policy app_entries_insert on public.app_entries
  for insert with check (public.can_write_business(business_id));

drop policy if exists app_audit_expenses_insert on public.app_audit_expenses;
create policy app_audit_expenses_insert on public.app_audit_expenses
  for insert with check (public.can_write_business(business_id));

-- ----------------------------------------------------------------
-- 3. Also re-create the UPDATE policies for the same tables, in case
--    they share the same gap. (Idempotent — replaces if present.)
-- ----------------------------------------------------------------

drop policy if exists app_books_update on public.app_books;
create policy app_books_update on public.app_books
  for update using (public.can_write_business(business_id))
              with check (public.can_write_business(business_id));

drop policy if exists app_account_groups_update on public.app_account_groups;
create policy app_account_groups_update on public.app_account_groups
  for update using (public.can_write_business(business_id))
              with check (public.can_write_business(business_id));

drop policy if exists app_cash_accounts_update on public.app_cash_accounts;
create policy app_cash_accounts_update on public.app_cash_accounts
  for update using (public.can_write_business(business_id))
              with check (public.can_write_business(business_id));

drop policy if exists app_parties_update on public.app_parties;
create policy app_parties_update on public.app_parties
  for update using (public.can_write_business(business_id))
              with check (public.can_write_business(business_id));

drop policy if exists app_categories_update on public.app_categories;
create policy app_categories_update on public.app_categories
  for update using (public.can_write_business(business_id))
              with check (public.can_write_business(business_id));

drop policy if exists app_entries_update on public.app_entries;
create policy app_entries_update on public.app_entries
  for update using (public.can_write_business(business_id))
              with check (public.can_write_business(business_id));

drop policy if exists app_audit_expenses_update on public.app_audit_expenses;
create policy app_audit_expenses_update on public.app_audit_expenses
  for update using (public.can_write_business(business_id))
              with check (public.can_write_business(business_id));

-- ----------------------------------------------------------------
-- 4. Same for DELETE — also gated on can_write_business.
-- ----------------------------------------------------------------

drop policy if exists app_books_delete on public.app_books;
create policy app_books_delete on public.app_books
  for delete using (public.can_write_business(business_id));

drop policy if exists app_account_groups_delete on public.app_account_groups;
create policy app_account_groups_delete on public.app_account_groups
  for delete using (public.can_write_business(business_id));

drop policy if exists app_cash_accounts_delete on public.app_cash_accounts;
create policy app_cash_accounts_delete on public.app_cash_accounts
  for delete using (public.can_write_business(business_id));

drop policy if exists app_parties_delete on public.app_parties;
create policy app_parties_delete on public.app_parties
  for delete using (public.can_write_business(business_id));

drop policy if exists app_categories_delete on public.app_categories;
create policy app_categories_delete on public.app_categories
  for delete using (public.can_write_business(business_id));

drop policy if exists app_entries_delete on public.app_entries;
create policy app_entries_delete on public.app_entries
  for delete using (public.can_write_business(business_id));

drop policy if exists app_audit_expenses_delete on public.app_audit_expenses;
create policy app_audit_expenses_delete on public.app_audit_expenses
  for delete using (public.can_write_business(business_id));

-- ----------------------------------------------------------------
-- 5. SELECT policies are likely also missing. Add them too.
-- ----------------------------------------------------------------

drop policy if exists app_books_select on public.app_books;
create policy app_books_select on public.app_books
  for select using (public.can_read_business(business_id));

drop policy if exists app_account_groups_select on public.app_account_groups;
create policy app_account_groups_select on public.app_account_groups
  for select using (public.can_read_business(business_id));

drop policy if exists app_cash_accounts_select on public.app_cash_accounts;
create policy app_cash_accounts_select on public.app_cash_accounts
  for select using (public.can_read_business(business_id));

drop policy if exists app_parties_select on public.app_parties;
create policy app_parties_select on public.app_parties
  for select using (public.can_read_business(business_id));

drop policy if exists app_categories_select on public.app_categories;
create policy app_categories_select on public.app_categories
  for select using (public.can_read_business(business_id));

drop policy if exists app_entries_select on public.app_entries;
create policy app_entries_select on public.app_entries
  for select using (public.can_read_business(business_id));

drop policy if exists app_audit_expenses_select on public.app_audit_expenses;
create policy app_audit_expenses_select on public.app_audit_expenses
  for select using (public.can_read_business(business_id));

-- ----------------------------------------------------------------
-- DONE
-- ----------------------------------------------------------------
-- Run the diagnostic query from earlier to verify all 10 tables now
-- have INSERT policies:
--
--   select c.relname, p.polname, pg_get_expr(p.polwithcheck, p.polrelid)
--   from pg_policy p
--   join pg_class c on c.oid = p.polrelid
--   join pg_namespace n on n.oid = c.relnamespace
--   where n.nspname = 'public' and c.relname like 'app_%' and p.polcmd = 'a'
--   order by c.relname;
--
-- You should see 10 rows now (was 3).
