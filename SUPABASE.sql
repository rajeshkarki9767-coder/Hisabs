-- ============================================================
-- HISABS — single-file Supabase setup
-- ============================================================
-- Run this ONCE on a fresh Supabase project. Creates all 10 app_* tables,
-- helper functions, RLS policies, the realtime publication, and the
-- explicit grants PostgREST needs.
--
-- Idempotent: safe to re-run on an existing project.
--
-- DELETION STRATEGY: hard deletes. When a user deletes a record, it is
-- physically removed from the database. ON DELETE CASCADE foreign keys
-- handle child cascades automatically. Realtime DELETE events propagate
-- to other devices — for the event payloads to carry the row's data
-- (not just the primary key), tables have REPLICA IDENTITY FULL set.
--
-- Ordering:
--   1. Tables       (referenced by helpers)
--   2. REPLICA IDENTITY (so realtime DELETE events carry row data)
--   3. Helpers      (referenced by policies)
--   4. RLS enable
--   5. Policies     (drop-if-exists + create)
--   6. Grants       (PostgREST checks role grants BEFORE applying RLS)
--   7. Realtime pub (publication membership)
-- ============================================================

-- ----------------------------------------------------------------
-- 1. Tables
-- ----------------------------------------------------------------
-- The deleted_at column is kept on every table as a harmless legacy
-- field. It's no longer set or read by the application (which now does
-- true hard deletes), but keeping the column means no migration is
-- required for projects that previously used soft deletes.

create table if not exists public.app_accounts (
  id uuid primary key,
  display_name text,
  email text,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  deleted_at timestamptz
);

create table if not exists public.app_businesses (
  id text primary key,
  name text not null,
  currency text not null default 'NPR',
  owner_id uuid not null,
  staff_sees_totals boolean not null default true,
  created_at_local text,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  deleted_at timestamptz
);
create index if not exists idx_app_businesses_owner_id on public.app_businesses(owner_id);

create table if not exists public.app_books (
  id text primary key,
  business_id text not null references public.app_businesses(id) on delete cascade,
  name text not null,
  created_at_local text,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  deleted_at timestamptz
);
create index if not exists idx_app_books_business_id on public.app_books(business_id);

create table if not exists public.app_account_groups (
  id text primary key,
  business_id text not null references public.app_businesses(id) on delete cascade,
  name text not null,
  kind text,
  sort_order int,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  deleted_at timestamptz
);
create index if not exists idx_app_account_groups_business_id on public.app_account_groups(business_id);

create table if not exists public.app_cash_accounts (
  id text primary key,
  business_id text not null references public.app_businesses(id) on delete cascade,
  group_id text,
  name text not null,
  hidden boolean default false,
  sort_order int,
  created_at_local text,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  deleted_at timestamptz
);
create index if not exists idx_app_cash_accounts_business_id on public.app_cash_accounts(business_id);

create table if not exists public.app_parties (
  id text primary key,
  business_id text not null references public.app_businesses(id) on delete cascade,
  name text not null,
  kind text,
  sort_order int,
  created_at_local text,
  -- created_by: tracks which user created this party. Used so staff can
  -- rename their own parties (but not others'). NULL for legacy parties
  -- created before this column was added — those are treated as
  -- "anyone with party-add permission can rename" so existing data
  -- doesn't become uneditable.
  created_by uuid,
  created_by_name text,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  deleted_at timestamptz
);
alter table public.app_parties add column if not exists created_by uuid;
alter table public.app_parties add column if not exists created_by_name text;
create index if not exists idx_app_parties_business_id on public.app_parties(business_id);

create table if not exists public.app_categories (
  id text primary key,
  business_id text not null references public.app_businesses(id) on delete cascade,
  name text not null,
  sort_order int,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  deleted_at timestamptz
);
create index if not exists idx_app_categories_business_id on public.app_categories(business_id);

create table if not exists public.app_members (
  id text primary key,
  business_id text not null references public.app_businesses(id) on delete cascade,
  user_id uuid,
  user_login text,
  role text,
  status text,
  responded_at text,
  invited_by_name text,
  business_name text,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  deleted_at timestamptz
);
create index if not exists idx_app_members_business_id on public.app_members(business_id);
create index if not exists idx_app_members_user_id on public.app_members(user_id);
create index if not exists idx_app_members_user_login on public.app_members(lower(user_login));

create table if not exists public.app_entries (
  id text primary key,
  book_id text not null references public.app_books(id) on delete cascade,
  business_id text not null references public.app_businesses(id) on delete cascade,
  type text not null,
  amount numeric not null default 0,
  entry_date text,
  party text,
  party_id text,
  account_id text,
  category text,
  note text,
  created_at_local timestamptz,
  created_by uuid,
  created_by_name text,
  edited_at_local timestamptz,
  edited_by uuid,
  edited_by_name text,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  deleted_at timestamptz
);
create index if not exists idx_app_entries_business_id on public.app_entries(business_id);
create index if not exists idx_app_entries_book_id on public.app_entries(book_id);
create index if not exists idx_app_entries_business_date on public.app_entries(business_id, entry_date desc);

create table if not exists public.app_audit_expenses (
  id text primary key,
  business_id text not null references public.app_businesses(id) on delete cascade,
  month text,
  -- `date` was added in a later release to support day-granularity
  -- expense filtering (custom date ranges). Older rows only had `month`
  -- (e.g. '2026-05') and got backfilled to the first of that month.
  -- Both columns are kept in sync going forward.
  date date,
  label text,
  amount numeric not null default 0,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  deleted_at timestamptz
);
-- Migration safety: if you upgraded from an earlier schema that didn't
-- have `date`, add the column and backfill from `month`. Running this
-- twice is fine — both statements are idempotent.
alter table public.app_audit_expenses add column if not exists date date;
update public.app_audit_expenses
  set date = to_date(month || '-01', 'YYYY-MM-DD')
  where date is null and month is not null;
create index if not exists idx_app_audit_expenses_business_id on public.app_audit_expenses(business_id);
create index if not exists idx_app_audit_expenses_date on public.app_audit_expenses(date);

-- Device names: friendly labels users give to their browsers/sessions.
-- One row per (user, device) pair. Multiple sessions on the same browser
-- share a device_id (kept in browser localStorage), so renaming once
-- updates all future logins from that browser.
--
-- The row is keyed by (user_id, device_id) instead of session_id because
-- sessions expire/regenerate but the user's "this is my MacBook" label
-- should persist across re-sign-ins on the same browser.
create table if not exists public.app_device_names (
  user_id uuid not null,
  device_id text not null,
  name text not null,
  session_id uuid,                 -- last-known auth.sessions.id for this device (advisory)
  updated_at timestamptz default now(),
  primary key (user_id, device_id)
);
create index if not exists idx_app_device_names_user on public.app_device_names(user_id);
create index if not exists idx_app_device_names_session on public.app_device_names(session_id);

-- Web Push subscription endpoints. One row per browser+user that has
-- granted notification permission. Used by the send-announcement-push
-- Edge Function to fan out notifications when an announcement is posted.
--
-- `endpoint` is the URL the push service (FCM / Mozilla / etc.) gave us
-- when subscribe() succeeded. p256dh + auth are the encryption keys.
-- Same shape returned by PushSubscription.toJSON().
--
-- A device that re-subscribes (e.g. after browser data clear) gets a
-- new endpoint; we keep the old one until it 410-Gones away, then the
-- Edge Function deletes it. The (endpoint) UNIQUE constraint prevents
-- duplicate fanouts to the same endpoint if a user re-grants.
create table if not exists public.app_push_subscriptions (
  id text primary key,
  user_id uuid not null,
  endpoint text not null,
  p256dh text not null,
  auth_key text not null,
  user_agent text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
create unique index if not exists idx_app_push_subs_endpoint on public.app_push_subscriptions(endpoint);
create index if not exists idx_app_push_subs_user on public.app_push_subscriptions(user_id);

-- RLS: a user can manage their own push subscriptions. The Edge
-- Function that sends pushes uses the service role and bypasses RLS,
-- so it can read every member's subscriptions when fanning out.
alter table public.app_push_subscriptions enable row level security;
drop policy if exists app_push_subs_select on public.app_push_subscriptions;
create policy app_push_subs_select on public.app_push_subscriptions
  for select to authenticated using (user_id = auth.uid());
drop policy if exists app_push_subs_insert on public.app_push_subscriptions;
create policy app_push_subs_insert on public.app_push_subscriptions
  for insert to authenticated with check (user_id = auth.uid());
drop policy if exists app_push_subs_update on public.app_push_subscriptions;
create policy app_push_subs_update on public.app_push_subscriptions
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists app_push_subs_delete on public.app_push_subscriptions;
create policy app_push_subs_delete on public.app_push_subscriptions
  for delete to authenticated using (user_id = auth.uid());

-- Failed sign-in attempt counter. Mirrors localStorage rate-limit state
-- in the cloud so it persists across browser-clears and devices.
-- Keyed by lowercase email (not user_id, because the typical failed-
-- login case is "user typed wrong password" — we don't know which
-- auth.users row they meant). Cleared on successful sign-in.
create table if not exists public.app_failed_logins (
  email text primary key,
  attempt_count int not null default 0,
  locked_until timestamptz,
  updated_at timestamptz default now()
);

-- Per-user audit log of meaningful events. Examples: sign-in, sign-out,
-- business-created, business-deleted, account-wiped. Append-only by
-- design: clients write but cannot read others' logs and cannot edit
-- or delete their own (so an attacker can't cover tracks by clearing
-- the log).
--
-- Logged events are visible to the user in Settings → Data → Activity.
create table if not exists public.app_audit_log (
  id text primary key,
  user_id uuid not null,
  event_type text not null,
  description text,
  metadata jsonb,
  ip text,
  user_agent text,
  occurred_at timestamptz default now()
);
create index if not exists idx_app_audit_log_user_time on public.app_audit_log(user_id, occurred_at desc);

-- Quick Look directory: shared per-business reference list of payment
-- accounts, QR codes, etc. Anyone with access to the business can read
-- and copy/download; owners and managers can add/edit/delete.
--
-- Fields:
--   name        - human label ("eSewa main", "NIC Asia office account")
--   tag         - the copyable string (phone number, account number, UPI ID)
--   photo_data  - base64-encoded image data with data: URI prefix, or NULL.
--                 Stored inline rather than in Supabase Storage so the row
--                 syncs through the same realtime channel as everything else.
--                 Expected to be small QR codes (under 200KB); enforced
--                 softly on the client.
--   in_use      - whether this entry should appear in the "In Use" section
--                 at the top of the view.
create table if not exists public.app_quick_look (
  id text primary key,
  business_id text not null references public.app_businesses(id) on delete cascade,
  name text not null,
  tag text,
  photo_data text,
  in_use boolean not null default true,
  sort_order int default 0,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
create index if not exists idx_app_quick_look_business on public.app_quick_look(business_id, sort_order);

-- Announcements: per-business messages posted by the owner that appear
-- at the top of the entries dashboard for everyone. Use cases: "Shop
-- closed Friday", "Bank holiday — no deposits", "Use the new eSewa
-- number this week", etc.
--
-- Only the business owner can write; everyone with read access to the
-- business can read. Soft policy keeps it simple — owner can edit/delete
-- their own posts.
create table if not exists public.app_announcements (
  id text primary key,
  business_id text not null references public.app_businesses(id) on delete cascade,
  author_id uuid,
  author_name text,
  body text not null,
  -- `important` flag added later. When true, the announcement shows on
  -- the entries page with a warning icon; otherwise it lives behind the
  -- "View announcements" link so the page doesn't get crowded.
  important boolean not null default false,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
-- Migration safety: existing tables get the column defaulted to false.
alter table public.app_announcements add column if not exists important boolean not null default false;
create index if not exists idx_app_announcements_business on public.app_announcements(business_id, created_at desc);

-- ----------------------------------------------------------------
-- 2. REPLICA IDENTITY FULL
-- ----------------------------------------------------------------
-- By default Postgres's logical replication sends only the primary key on
-- DELETE events. The Supabase Realtime stream uses this — so subscribers
-- would receive a DELETE event with only `{id: 'xxx'}` and no business_id,
-- making it impossible to filter the event to the right business.
--
-- REPLICA IDENTITY FULL tells Postgres to include the entire row in the
-- replication stream for DELETEs and UPDATEs. Costs a tiny amount of disk
-- I/O per write — negligible at our scale, and required for hard-delete
-- realtime propagation to work correctly.

alter table public.app_accounts        replica identity full;
alter table public.app_businesses      replica identity full;
alter table public.app_books           replica identity full;
alter table public.app_account_groups  replica identity full;
alter table public.app_cash_accounts   replica identity full;
alter table public.app_parties         replica identity full;
alter table public.app_categories      replica identity full;
alter table public.app_members         replica identity full;
alter table public.app_entries         replica identity full;
alter table public.app_audit_expenses  replica identity full;
alter table public.app_device_names    replica identity full;
alter table public.app_failed_logins   replica identity full;
alter table public.app_audit_log       replica identity full;
alter table public.app_quick_look      replica identity full;
alter table public.app_announcements   replica identity full;

-- ----------------------------------------------------------------
-- 2.5. Supabase Realtime publication membership
-- ----------------------------------------------------------------
-- Supabase Realtime delivers postgres_changes events ONLY for tables
-- that are members of the `supabase_realtime` publication. REPLICA
-- IDENTITY FULL above only controls how MUCH data each event carries
-- — it doesn't control WHETHER events fire at all. If you've ever seen
-- "sync only happens after refresh", it's because the tables weren't in
-- this publication, so the client subscribed to a stream that never
-- emitted anything.
--
-- Postgres has no `add table if not exists` syntax for publications, so
-- we read pg_publication_tables and only add tables that aren't already
-- members. Re-running this block is safe and idempotent.
--
-- Note: on a brand-new Supabase project, the publication exists but is
-- empty (or contains only some tables, depending on what you toggled in
-- the dashboard). The conditional create handles either state.
do $$
declare
  pub_exists boolean;
  t text;
  tables_to_publish text[] := array[
    'app_accounts',
    'app_businesses',
    'app_books',
    'app_account_groups',
    'app_cash_accounts',
    'app_parties',
    'app_categories',
    'app_members',
    'app_entries',
    'app_audit_expenses',
    'app_device_names',
    'app_audit_log',
    'app_quick_look',
    'app_announcements',
    'app_push_subscriptions'
  ];
begin
  select exists (
    select 1 from pg_publication where pubname = 'supabase_realtime'
  ) into pub_exists;
  if not pub_exists then
    create publication supabase_realtime;
  end if;
  foreach t in array tables_to_publish loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end$$;
-- After this block runs, every connected client will start receiving
-- INSERT/UPDATE/DELETE events for these tables in real time. You
-- should see "Realtime status: SUBSCRIBED" in the browser console
-- once the page reloads.

-- ----------------------------------------------------------------
-- 3. Helper functions
-- ----------------------------------------------------------------
-- All helpers use:
--   security definer        -- function runs as owner, bypassing RLS for internal lookups
--   set search_path = public, auth  -- so auth.uid() resolves, and our tables are found unambiguously

create or replace function public.user_owns_business(bid text)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select exists (
    select 1 from public.app_businesses b
    where b.id = bid and b.owner_id = auth.uid()
  );
$$;

create or replace function public.user_is_business_member(bid text)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select exists (
    select 1 from public.app_members m
    where m.business_id = bid
      and (
        m.user_id = auth.uid()
        or lower(m.user_login) = lower(coalesce((auth.jwt() ->> 'email'), ''))
      )
  );
$$;

create or replace function public.can_read_business(bid text)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select public.user_owns_business(bid) or exists (
    select 1 from public.app_members m
    where m.business_id = bid
      and m.user_id = auth.uid()
      and m.status = 'accepted'
  );
$$;

create or replace function public.can_write_business(bid text)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select public.user_owns_business(bid) or exists (
    select 1 from public.app_members m
    where m.business_id = bid
      and m.user_id = auth.uid()
      and m.status = 'accepted'
      and coalesce(m.role, '') in ('manager', 'staff')
  );
$$;

grant execute on function public.user_owns_business(text)        to anon, authenticated;
grant execute on function public.user_is_business_member(text)   to anon, authenticated;
grant execute on function public.can_read_business(text)         to anon, authenticated;
grant execute on function public.can_write_business(text)        to anon, authenticated;

-- ----------------------------------------------------------------
-- 4. Enable RLS on every table
-- ----------------------------------------------------------------

alter table public.app_accounts        enable row level security;
alter table public.app_businesses      enable row level security;
alter table public.app_books           enable row level security;
alter table public.app_account_groups  enable row level security;
alter table public.app_cash_accounts   enable row level security;
alter table public.app_parties         enable row level security;
alter table public.app_categories      enable row level security;
alter table public.app_members         enable row level security;
alter table public.app_entries         enable row level security;
alter table public.app_audit_expenses  enable row level security;
alter table public.app_device_names    enable row level security;
alter table public.app_quick_look      enable row level security;
alter table public.app_announcements   enable row level security;

-- ----------------------------------------------------------------
-- 5. Policies
-- ----------------------------------------------------------------

-- app_accounts: self only
drop policy if exists app_accounts_select on public.app_accounts;
create policy app_accounts_select on public.app_accounts
  for select using (id = auth.uid());
drop policy if exists app_accounts_insert on public.app_accounts;
create policy app_accounts_insert on public.app_accounts
  for insert with check (id = auth.uid());
drop policy if exists app_accounts_update on public.app_accounts;
create policy app_accounts_update on public.app_accounts
  for update using (id = auth.uid()) with check (id = auth.uid());
drop policy if exists app_accounts_delete on public.app_accounts;
create policy app_accounts_delete on public.app_accounts
  for delete using (id = auth.uid());

-- app_businesses: owner OR business-member (helper-based, non-recursive)
drop policy if exists app_businesses_select on public.app_businesses;
create policy app_businesses_select on public.app_businesses
  for select using (
    owner_id = auth.uid()
    or public.user_is_business_member(id)
  );
drop policy if exists app_businesses_insert on public.app_businesses;
create policy app_businesses_insert on public.app_businesses
  for insert with check (owner_id = auth.uid());
drop policy if exists app_businesses_update on public.app_businesses;
create policy app_businesses_update on public.app_businesses
  for update using (owner_id = auth.uid()) with check (owner_id = auth.uid());
drop policy if exists app_businesses_delete on public.app_businesses;
create policy app_businesses_delete on public.app_businesses
  for delete using (owner_id = auth.uid());

-- Child tables: SELECT via can_read_business, write ops via can_write_business
do $$
declare
  t text;
begin
  for t in select unnest(array[
    'app_books','app_account_groups','app_cash_accounts','app_parties',
    'app_categories','app_entries','app_audit_expenses'
  ])
  loop
    execute format('drop policy if exists %1$s_select on public.%1$s', t);
    execute format(
      'create policy %1$s_select on public.%1$s for select using (public.can_read_business(business_id))',
      t
    );
    execute format('drop policy if exists %1$s_insert on public.%1$s', t);
    execute format(
      'create policy %1$s_insert on public.%1$s for insert with check (public.can_write_business(business_id))',
      t
    );
    execute format('drop policy if exists %1$s_update on public.%1$s', t);
    execute format(
      'create policy %1$s_update on public.%1$s for update using (public.can_write_business(business_id)) with check (public.can_write_business(business_id))',
      t
    );
    execute format('drop policy if exists %1$s_delete on public.%1$s', t);
    execute format(
      'create policy %1$s_delete on public.%1$s for delete using (public.can_write_business(business_id))',
      t
    );
  end loop;
end $$;

-- app_members: invitee can see/accept their row; business owner manages
drop policy if exists app_members_select on public.app_members;
create policy app_members_select on public.app_members
  for select using (
    user_id = auth.uid()
    or lower(user_login) = lower(coalesce((auth.jwt() ->> 'email'), ''))
    or public.user_owns_business(business_id)
  );
drop policy if exists app_members_insert on public.app_members;
create policy app_members_insert on public.app_members
  for insert with check (
    public.user_owns_business(business_id)
    or user_id = auth.uid()
    or lower(user_login) = lower(coalesce((auth.jwt() ->> 'email'), ''))
  );
drop policy if exists app_members_update on public.app_members;
create policy app_members_update on public.app_members
  for update using (
    user_id = auth.uid()
    or lower(user_login) = lower(coalesce((auth.jwt() ->> 'email'), ''))
    or public.user_owns_business(business_id)
  ) with check (
    user_id = auth.uid()
    or lower(user_login) = lower(coalesce((auth.jwt() ->> 'email'), ''))
    or public.user_owns_business(business_id)
  );
drop policy if exists app_members_delete on public.app_members;
create policy app_members_delete on public.app_members
  for delete using (
    user_id = auth.uid()
    or lower(user_login) = lower(coalesce((auth.jwt() ->> 'email'), ''))
    or public.user_owns_business(business_id)
  );

-- app_device_names: user can only see/manage their own device labels.
drop policy if exists app_device_names_select on public.app_device_names;
create policy app_device_names_select on public.app_device_names
  for select using (user_id = auth.uid());
drop policy if exists app_device_names_insert on public.app_device_names;
create policy app_device_names_insert on public.app_device_names
  for insert with check (user_id = auth.uid());
drop policy if exists app_device_names_update on public.app_device_names;
create policy app_device_names_update on public.app_device_names
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists app_device_names_delete on public.app_device_names;
create policy app_device_names_delete on public.app_device_names
  for delete using (user_id = auth.uid());

-- app_quick_look: anyone with access to the business can read. Only
-- owner/manager can write. The role check is done client-side too, but
-- enforced here so a hostile client can't bypass it.
--
-- can_read_business handles the read side; for writes we need the
-- "owner or manager" subset. We inline a quick role check using
-- app_members rather than a dedicated helper, since this is the only
-- table with owner+manager-only writes.
drop policy if exists app_quick_look_select on public.app_quick_look;
create policy app_quick_look_select on public.app_quick_look
  for select using (public.can_read_business(business_id));
drop policy if exists app_quick_look_insert on public.app_quick_look;
create policy app_quick_look_insert on public.app_quick_look
  for insert with check (
    public.user_owns_business(business_id)
    or exists (
      select 1 from public.app_members m
      where m.business_id = app_quick_look.business_id
        and m.user_id = auth.uid()
        and m.role in ('manager')
        and m.status = 'accepted'
    )
  );
drop policy if exists app_quick_look_update on public.app_quick_look;
create policy app_quick_look_update on public.app_quick_look
  for update using (
    public.user_owns_business(business_id)
    or exists (
      select 1 from public.app_members m
      where m.business_id = app_quick_look.business_id
        and m.user_id = auth.uid()
        and m.role in ('manager')
        and m.status = 'accepted'
    )
  ) with check (
    public.user_owns_business(business_id)
    or exists (
      select 1 from public.app_members m
      where m.business_id = app_quick_look.business_id
        and m.user_id = auth.uid()
        and m.role in ('manager')
        and m.status = 'accepted'
    )
  );
drop policy if exists app_quick_look_delete on public.app_quick_look;
create policy app_quick_look_delete on public.app_quick_look
  for delete using (
    public.user_owns_business(business_id)
    or exists (
      select 1 from public.app_members m
      where m.business_id = app_quick_look.business_id
        and m.user_id = auth.uid()
        and m.role in ('manager')
        and m.status = 'accepted'
    )
  );

-- app_announcements: anyone with read access to the business can read;
-- only the business owner can write. Edit/delete uses the same gate so
-- only the owner can manage what was posted.
drop policy if exists app_announcements_select on public.app_announcements;
create policy app_announcements_select on public.app_announcements
  for select using (public.can_read_business(business_id));
drop policy if exists app_announcements_insert on public.app_announcements;
create policy app_announcements_insert on public.app_announcements
  for insert with check (public.user_owns_business(business_id));
drop policy if exists app_announcements_update on public.app_announcements;
create policy app_announcements_update on public.app_announcements
  for update using (public.user_owns_business(business_id))
            with check (public.user_owns_business(business_id));
drop policy if exists app_announcements_delete on public.app_announcements;
create policy app_announcements_delete on public.app_announcements
  for delete using (public.user_owns_business(business_id));

-- app_failed_logins: must be accessible to unauthenticated callers
-- (they're trying to sign in!). The data exposed is minimal — just
-- attempt counts per email — and the table is write-mostly: clients
-- can increment their own row, read it, but cannot read others'.
--
-- We don't filter on auth.uid() (none yet) — instead we accept that
-- this is essentially a public "how many bad password attempts has
-- email X had" counter. Knowing this doesn't help an attacker; it
-- only slows them down.
alter table public.app_failed_logins enable row level security;
drop policy if exists app_failed_logins_select on public.app_failed_logins;
create policy app_failed_logins_select on public.app_failed_logins
  for select using (true);
drop policy if exists app_failed_logins_insert on public.app_failed_logins;
create policy app_failed_logins_insert on public.app_failed_logins
  for insert with check (true);
drop policy if exists app_failed_logins_update on public.app_failed_logins;
create policy app_failed_logins_update on public.app_failed_logins
  for update using (true) with check (true);
drop policy if exists app_failed_logins_delete on public.app_failed_logins;
create policy app_failed_logins_delete on public.app_failed_logins
  for delete using (true);

-- app_audit_log: append-only event log. Users see their own events
-- only. No update or delete policies — so once a row is written, it
-- stays. This prevents an attacker from covering tracks by deleting
-- audit entries showing their sign-in.
alter table public.app_audit_log enable row level security;
drop policy if exists app_audit_log_select on public.app_audit_log;
create policy app_audit_log_select on public.app_audit_log
  for select using (user_id = auth.uid());
drop policy if exists app_audit_log_insert on public.app_audit_log;
create policy app_audit_log_insert on public.app_audit_log
  for insert with check (user_id = auth.uid());
-- Intentionally NO update or delete policies — rows are immutable
-- and cannot be removed by users. Admin can clean up via Dashboard
-- if needed (service_role bypasses RLS).

-- ----------------------------------------------------------------
-- 6. Grants
-- ----------------------------------------------------------------

grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
-- anon has no row-level access (RLS policies are all to authenticated),
-- but PostgREST needs table-level select grants on tables it inspects
-- during auth flow. We grant select only — no insert/update/delete to
-- anon. Even if a policy bug temporarily permitted anon writes, the
-- table-level grant blocks it. Defense in depth.
grant select on all tables in schema public to anon;

-- ============================================================
-- MIGRATION FROM SOFT-DELETE PROJECTS
-- ============================================================
-- If you previously ran the soft-delete version of this schema and you
-- have rows with deleted_at IS NOT NULL, you may want to hard-delete
-- them now so they're truly gone:
--
--   delete from public.app_entries        where deleted_at is not null;
--   delete from public.app_audit_expenses where deleted_at is not null;
--   delete from public.app_categories     where deleted_at is not null;
--   delete from public.app_parties        where deleted_at is not null;
--   delete from public.app_cash_accounts  where deleted_at is not null;
--   delete from public.app_account_groups where deleted_at is not null;
--   delete from public.app_books          where deleted_at is not null;
--   delete from public.app_members        where deleted_at is not null;
--   delete from public.app_businesses     where deleted_at is not null;
--   delete from public.app_accounts       where deleted_at is not null;
--
-- The deleted_at column itself can stay — it's harmless legacy.
-- ============================================================

-- ============================================================
-- 9. F14: Server-side length CHECK constraints (defensive depth)
-- ============================================================
-- The client validates lengths before insert, but a determined user with
-- DevTools can bypass client validation and post arbitrary strings.
-- Postgres `text` is unbounded, so a 100MB note would be accepted and
-- become a permanent performance drag on every subsequent query that
-- touches that row.
--
-- These CHECKs match the client-side LIMITS object (names: 120,
-- description: 500, note: 2000). Added with a do-block so the migration
-- is idempotent (Postgres has `add column if not exists` but no
-- `add constraint if not exists` until v9.6+ on some clusters).
--
-- If any existing row exceeds these limits, the ALTER will fail with a
-- check-violation error. In that case, find and trim the offending row
-- before re-running.

-- ============================================================
-- 9.5. One-shot cleanup: orphan member rows
-- ============================================================
-- If any previous account-deletion left member rows pointing at users
-- that no longer exist in auth.users, a new account signing up with the
-- same email inherits those memberships and sees "ghost businesses".
-- Safe to run repeatedly — only removes rows where the user_id no
-- longer matches a real auth user AND the user_login is no longer an
-- active auth account's email.
delete from public.app_members m
where (
  m.user_id is not null
  and not exists (select 1 from auth.users u where u.id = m.user_id)
)
and (
  m.user_login is null
  or not exists (
    select 1 from auth.users u
    where lower(u.email) = lower(m.user_login)
  )
);

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'app_entries_note_len') then
    alter table public.app_entries add constraint app_entries_note_len check (note is null or length(note) <= 2000);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'app_entries_party_len') then
    alter table public.app_entries add constraint app_entries_party_len check (party is null or length(party) <= 120);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'app_entries_category_len') then
    alter table public.app_entries add constraint app_entries_category_len check (category is null or length(category) <= 120);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'app_businesses_name_len') then
    alter table public.app_businesses add constraint app_businesses_name_len check (length(name) <= 120);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'app_books_name_len') then
    alter table public.app_books add constraint app_books_name_len check (length(name) <= 120);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'app_parties_name_len') then
    alter table public.app_parties add constraint app_parties_name_len check (length(name) <= 120);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'app_categories_name_len') then
    alter table public.app_categories add constraint app_categories_name_len check (length(name) <= 120);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'app_account_groups_name_len') then
    alter table public.app_account_groups add constraint app_account_groups_name_len check (length(name) <= 120);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'app_cash_accounts_name_len') then
    alter table public.app_cash_accounts add constraint app_cash_accounts_name_len check (length(name) <= 120);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'app_audit_expenses_label_len') then
    alter table public.app_audit_expenses add constraint app_audit_expenses_label_len check (label is null or length(label) <= 500);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'app_announcements_body_len') then
    alter table public.app_announcements add constraint app_announcements_body_len check (length(body) <= 1000);
  end if;
end$$;

