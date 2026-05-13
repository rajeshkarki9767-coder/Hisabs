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
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  deleted_at timestamptz
);
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
  label text,
  amount numeric not null default 0,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  deleted_at timestamptz
);
create index if not exists idx_app_audit_expenses_business_id on public.app_audit_expenses(business_id);

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

-- ----------------------------------------------------------------
-- 6. Grants
-- ----------------------------------------------------------------

grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant select, insert, update on all tables in schema public to anon;

-- ----------------------------------------------------------------
-- 7. Realtime publication
-- ----------------------------------------------------------------

do $$
declare
  t text;
begin
  for t in select unnest(array[
    'app_accounts','app_businesses','app_books','app_account_groups',
    'app_cash_accounts','app_parties','app_categories','app_members',
    'app_entries','app_audit_expenses'
  ])
  loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception when duplicate_object then null;
    when others then raise notice 'Could not add % to publication: %', t, sqlerrm;
    end;
  end loop;
end $$;

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
