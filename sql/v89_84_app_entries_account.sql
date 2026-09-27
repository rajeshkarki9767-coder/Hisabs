-- =====================================================================
-- v89.84 — app_entries.account (account NAME snapshot)
-- =====================================================================
-- WHY:
--   Entries store account_id (a live foreign-key-style reference). When an
--   account is deleted, the entry lost the account name entirely — it stopped
--   displaying and stopped being searchable, unlike party/category names which
--   are stored as text on the entry and survive deletion.
--
--   This adds an `account` text column that holds a snapshot of the account
--   name at write time (exactly parallel to the existing `party` column, which
--   snapshots the party name next to party_id). The client (build 2026.06.05+)
--   writes it on create/edit/transfer and backfills it on load.
--
-- SAFETY:
--   - Additive only. Nullable, no default backfill required (the client
--     backfills names from each device's synced accounts on load, and writes
--     the value on every subsequent upsert).
--   - Idempotent: safe to run more than once.
--   - Must be applied BEFORE deploying the matching client build, because the
--     client's app_entries upsert now includes this column; if the column is
--     absent, PostgREST rejects the write and entry sync breaks.
--
-- RUN: paste into the Supabase SQL editor and execute.
-- =====================================================================

alter table public.app_entries
  add column if not exists account text;

-- Optional one-time server-side backfill for entries whose account still
-- exists: copy the current account name into the snapshot. (The client also
-- does this on load, so this is just to populate the cloud immediately.)
update public.app_entries e
set account = a.name
from public.app_cash_accounts a
where e.account_id = a.id
  and e.account is null;

-- No RLS change needed: the column is covered by the existing app_entries
-- row-level policies (can_write_business / can_read_business).
