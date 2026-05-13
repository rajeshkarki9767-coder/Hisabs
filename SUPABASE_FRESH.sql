-- ============================================================
-- HISABS — single-file Supabase setup
-- ============================================================
-- Run this ONCE on a fresh Supabase project. Creates all 10 app_* tables,
-- their RLS policies, the helper functions, and the realtime publication.
-- Idempotent: safe to re-run (uses drop-if-exists + create or replace).
--
-- After this runs, the database is ready for Hisabs to connect to.
-- No further SQL needed.
-- ============================================================

-- ----------------------------------------------------------------
-- 0. Helper functions
-- ----------------------------------------------------------------
-- We need these defined BEFORE the tables (the table policies reference them).
-- security definer + search_path include both `public` and `auth` so the
-- functions can both query our tables AND call auth.uid().

create or replace function public.can_read_business(bid text)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select exists (
    select 1 from public.app_businesses b
    where b.id = bid
      and (
        b.owner_id = auth.uid()
        or exists (
          select 1 from public.app_members m
          where m.business_id = b.id
            and m.user_id = auth.uid()
            and m.status = 'accepted'
            and m.deleted_at is null
        )
      )
  );
$$;

create or replace function public.can_write_business(bid text)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select exists (
    select 1 from public.app_businesses b
    where b.id = bid and b.owner_id = auth.uid()
  ) or exists (
    select 1 from public.app_members m
    where m.business_id = bid
      and m.user_id = auth.uid()
      and m.status = 'accepted'
      and m.deleted_at is null
      and coalesce(m.role, '') in ('manager', 'staff')
  );
$$;

grant execute on function public.can_read_business(text) to anon, authenticated;
grant execute on function public.can_write_business(text) to anon, authenticated;

-- ----------------------------------------------------------------
-- 1. Tables
-- ----------------------------------------------------------------
-- Each app_* table has a text PK (Hisabs generates uids client-side),
-- a deleted_at column for soft deletes (so realtime UPDATE events
-- propagate deletes to other devices), and an updated_at for change
-- tracking. Children reference business_id directly for fast RLS.

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
-- 2. Enable RLS on every table
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
-- 3. Policies
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

-- app_businesses: owner = auth.uid()
drop policy if exists app_businesses_select on public.app_businesses;
create policy app_businesses_select on public.app_businesses
  for select using (
    owner_id = auth.uid()
    or exists (
      select 1 from public.app_members m
      where m.business_id = app_businesses.id
        and m.deleted_at is null
        and (
          (m.user_id = auth.uid() and m.status = 'accepted')
          or (m.user_id = auth.uid())
          or (lower(m.user_login) = lower(coalesce((auth.jwt() ->> 'email'), '')))
        )
    )
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

-- Child tables: select/insert/update/delete via can_*_business helpers
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

-- app_members has special rules: invitee can see their own pending row,
-- owner of the business can see/manage all rows for that business.
drop policy if exists app_members_select on public.app_members;
create policy app_members_select on public.app_members
  for select using (
    user_id = auth.uid()
    or lower(user_login) = lower(coalesce((auth.jwt() ->> 'email'), ''))
    or exists (
      select 1 from public.app_businesses b
      where b.id = app_members.business_id and b.owner_id = auth.uid()
    )
  );
drop policy if exists app_members_insert on public.app_members;
create policy app_members_insert on public.app_members
  for insert with check (
    exists (
      select 1 from public.app_businesses b
      where b.id = business_id and b.owner_id = auth.uid()
    )
  );
drop policy if exists app_members_update on public.app_members;
create policy app_members_update on public.app_members
  for update using (
    user_id = auth.uid()
    or lower(user_login) = lower(coalesce((auth.jwt() ->> 'email'), ''))
    or exists (
      select 1 from public.app_businesses b
      where b.id = app_members.business_id and b.owner_id = auth.uid()
    )
  );
drop policy if exists app_members_delete on public.app_members;
create policy app_members_delete on public.app_members
  for delete using (
    exists (
      select 1 from public.app_businesses b
      where b.id = app_members.business_id and b.owner_id = auth.uid()
    )
  );

-- ----------------------------------------------------------------
-- 4. Grants — required for PostgREST to even attempt these operations
-- ----------------------------------------------------------------
-- Without these grants, PostgREST returns 401/403 before RLS even runs.
-- Grant on schema first, then per-table.
grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant select, insert, update on all tables in schema public to anon;

-- ----------------------------------------------------------------
-- 5. Realtime publication
-- ----------------------------------------------------------------
-- Adds every app_* table to the supabase_realtime publication so
-- postgres_changes subscriptions deliver events.

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
-- DONE.
-- ============================================================
-- Verify by running:
--   select c.relname, count(*) from pg_policy p
--   join pg_class c on c.oid = p.polrelid
--   join pg_namespace n on n.oid = c.relnamespace
--   where n.nspname='public' and c.relname like 'app_%'
--   group by c.relname order by c.relname;
-- Should show 10 rows, each with policy_count between 3 and 5.
