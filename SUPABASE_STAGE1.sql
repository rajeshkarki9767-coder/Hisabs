-- ============================================================
-- HISABS — Stage 1 cloud schema
-- ============================================================
-- Run this once in Supabase Dashboard → SQL Editor → Run.
-- It is idempotent (uses IF NOT EXISTS / DROP IF EXISTS for policies)
-- so re-running it is safe.
--
-- Design notes:
-- • Each table mirrors one of the local arrays in Hisabs's `data` object.
-- • Every row has a primary-key `id` that is the same value as the local
--   record's id, so push/pull is just upsert-by-id with no remapping.
-- • Soft delete via `deleted_at` so a deletion on one device can sync to
--   others; rows with deleted_at NOT NULL are hidden everywhere.
-- • `updated_at` is updated automatically by a trigger so we have a server
--   timestamp for ordering and conflict resolution.
-- • Access control:
--     – `accounts` is per-user (read/write only your own row)
--     – `businesses` is readable by owner OR an accepted member
--     – everything else inherits "you can see it if you can see its business"
--     – members is special: you can see rows where you're the owner of the
--       business, OR rows where userLogin matches your email (so invitees
--       can find their pending invites).
--
-- This is Stage 1 of a staged multi-user real-time sync rollout. Stage 2
-- adds realtime subscriptions; Stage 3 adds invite RPCs; Stage 4 adds the
-- offline operations queue.
-- ============================================================

-- The old single-blob `backups` table from the prototype phase. We keep it
-- so users who already have a cloud backup don't lose access; new versions
-- use the per-record tables below. Safe to drop later once everyone has
-- migrated.
-- (No change needed here — leaving it alone.)

-- ----------------------------------------------------------------
-- Helper: trigger function to keep updated_at fresh on every UPDATE.
-- ----------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ----------------------------------------------------------------
-- accounts — per-user profile (name, login, joined date).
-- The cloud `auth.users` table holds the real identity. This is the
-- app-level profile shim so `me()` keeps working unchanged.
-- ----------------------------------------------------------------
create table if not exists public.app_accounts (
  id           uuid primary key references auth.users(id) on delete cascade,
  name         text not null,
  login        text not null,
  joined       date not null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
drop trigger if exists app_accounts_updated_at on public.app_accounts;
create trigger app_accounts_updated_at
  before update on public.app_accounts
  for each row execute function public.set_updated_at();

alter table public.app_accounts enable row level security;
drop policy if exists app_accounts_select_own on public.app_accounts;
drop policy if exists app_accounts_insert_own on public.app_accounts;
drop policy if exists app_accounts_update_own on public.app_accounts;
-- A user can also read OTHER users' profiles by login, so the invite UI can
-- display the invitee's name. Limit to non-sensitive columns by convention
-- (callers should select only name/login).
drop policy if exists app_accounts_select_any on public.app_accounts;
create policy app_accounts_select_any on public.app_accounts
  for select using (true);
create policy app_accounts_insert_own on public.app_accounts
  for insert with check (auth.uid() = id);
create policy app_accounts_update_own on public.app_accounts
  for update using (auth.uid() = id) with check (auth.uid() = id);

-- ----------------------------------------------------------------
-- businesses
-- ----------------------------------------------------------------
create table if not exists public.app_businesses (
  id                  text primary key,                       -- the local id (uid())
  name                text not null,
  currency            text not null default 'NPR',
  owner_id            uuid not null references auth.users(id) on delete cascade,
  staff_sees_totals   boolean not null default true,
  created_at_local    text,                                   -- the original local createdAt string
  deleted_at          timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);
create index if not exists app_businesses_owner_idx on public.app_businesses(owner_id);
drop trigger if exists app_businesses_updated_at on public.app_businesses;
create trigger app_businesses_updated_at
  before update on public.app_businesses
  for each row execute function public.set_updated_at();

alter table public.app_businesses enable row level security;

-- IMPORTANT: the businesses_select policy and the members_select policy
-- below reference each other through sub-selects. If we let those sub-
-- selects run with RLS active, Postgres detects mutual recursion and the
-- whole query fails ("infinite recursion in policy"). The fix is to put
-- the cross-table membership check in a SECURITY DEFINER function that
-- bypasses RLS for its own internal queries. Helper defined AFTER the
-- members table so it can reference it.

-- Forward declaration: we will rewrite these policies right after creating
-- app_members and the helper function. For now create permissive temporary
-- policies so the table can be created and used before the helpers exist.
-- (At the end of this file the "real" policies replace these.)
drop policy if exists app_businesses_select on public.app_businesses;
create policy app_businesses_select on public.app_businesses
  for select using (owner_id = auth.uid());

-- Only the owner can insert (and they set themselves as owner_id).
drop policy if exists app_businesses_insert on public.app_businesses;
create policy app_businesses_insert on public.app_businesses
  for insert with check (owner_id = auth.uid());

-- Update gate: owner only at first; we widen this to managers below once
-- app_members + the helper exists.
drop policy if exists app_businesses_update on public.app_businesses;
create policy app_businesses_update on public.app_businesses
  for update using (owner_id = auth.uid())
              with check (owner_id = auth.uid());

drop policy if exists app_businesses_delete on public.app_businesses;
create policy app_businesses_delete on public.app_businesses
  for delete using (owner_id = auth.uid());

-- ----------------------------------------------------------------
-- members — who's in which business and at what role.
-- ----------------------------------------------------------------
create table if not exists public.app_members (
  id            text primary key,
  business_id   text not null references public.app_businesses(id) on delete cascade,
  -- user_id is set once the invitee actually signs in; until then it's null
  -- and only user_login is set. This lets invites work for users who don't
  -- have an account yet.
  user_id       uuid references auth.users(id) on delete set null,
  user_login    text not null,                                -- the invitee's email
  role          text not null check (role in ('owner','manager','staff','viewer')),
  status        text not null default 'pending' check (status in ('pending','accepted','declined')),
  responded_at  timestamptz,
  deleted_at    timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists app_members_biz_idx on public.app_members(business_id);
create index if not exists app_members_user_idx on public.app_members(user_id);
create index if not exists app_members_login_idx on public.app_members(user_login);
drop trigger if exists app_members_updated_at on public.app_members;
create trigger app_members_updated_at
  before update on public.app_members
  for each row execute function public.set_updated_at();

alter table public.app_members enable row level security;

-- IMPORTANT (same as businesses above): the "real" policies need to query
-- across both tables, which would recurse. We use SECURITY DEFINER helpers
-- defined right after this. Until then, owner-only initial policies.

drop policy if exists app_members_select on public.app_members;
create policy app_members_select on public.app_members
  for select using (
    user_id = auth.uid()
    or lower(user_login) = lower(coalesce((auth.jwt() ->> 'email'), ''))
  );

-- Only the business owner can insert new member rows (invitations).
drop policy if exists app_members_insert on public.app_members;
create policy app_members_insert on public.app_members
  for insert with check (
    -- Direct owner check, no cross-table recursion.
    business_id in (select id from public.app_businesses where owner_id = auth.uid())
  );

-- The invitee can update their own row (to accept/decline).
drop policy if exists app_members_update on public.app_members;
create policy app_members_update on public.app_members
  for update using (
    user_id = auth.uid()
    or lower(user_login) = lower(coalesce((auth.jwt() ->> 'email'), ''))
    or business_id in (select id from public.app_businesses where owner_id = auth.uid())
  );

drop policy if exists app_members_delete on public.app_members;
create policy app_members_delete on public.app_members
  for delete using (
    business_id in (select id from public.app_businesses where owner_id = auth.uid())
  );

-- ----------------------------------------------------------------
-- Reusable helper: can the current user read/write a given business?
-- Used by RLS policies on every business-scoped table below.
-- ----------------------------------------------------------------
create or replace function public.can_read_business(bid text)
returns boolean language sql stable security definer as $$
  select exists (
    select 1 from public.app_businesses b
    where b.id = bid
      and (
        b.owner_id = auth.uid()
        or exists (
          select 1 from public.app_members m
          where m.business_id = bid
            and m.user_id = auth.uid()
            and m.status = 'accepted'
            and m.deleted_at is null
        )
      )
  );
$$;

create or replace function public.can_write_business(bid text)
returns boolean language sql stable security definer as $$
  -- Owner, manager, or staff can write. Viewer cannot.
  -- Conflict-of-interest: this function is used for INSERT/UPDATE policies,
  -- so it must be conservative — staff are allowed to write entries and
  -- parties; finer per-table gates (e.g. only managers can change accounts)
  -- are enforced in app code, not at the DB layer. Stage 1 keeps the DB
  -- rule simple: any non-viewer can write.
  select exists (
    select 1 from public.app_businesses b
    where b.id = bid and b.owner_id = auth.uid()
  ) or exists (
    select 1 from public.app_members m
    where m.business_id = bid
      and m.user_id = auth.uid()
      and m.status = 'accepted'
      and m.deleted_at is null
      and m.role in ('owner','manager','staff')
  );
$$;

-- ----------------------------------------------------------------
-- Now that the SECURITY DEFINER helpers exist, replace the temporary
-- owner-only policies on businesses and members with team-aware ones
-- that use the helpers. SECURITY DEFINER bypasses RLS in the inner
-- queries, breaking the recursion.
-- ----------------------------------------------------------------

drop policy if exists app_businesses_select on public.app_businesses;
create policy app_businesses_select on public.app_businesses
  for select using (public.can_read_business(id));

drop policy if exists app_businesses_update on public.app_businesses;
create policy app_businesses_update on public.app_businesses
  for update using (
    owner_id = auth.uid()
    or exists (
      select 1 from public.app_members m
      where m.business_id = app_businesses.id
        and m.user_id = auth.uid()
        and m.role = 'manager'
        and m.status = 'accepted'
        and m.deleted_at is null
    )
  ) with check (
    owner_id = auth.uid()
    or exists (
      select 1 from public.app_members m
      where m.business_id = app_businesses.id
        and m.user_id = auth.uid()
        and m.role = 'manager'
        and m.status = 'accepted'
        and m.deleted_at is null
    )
  );

-- Members: team members can see other team members.
drop policy if exists app_members_select on public.app_members;
create policy app_members_select on public.app_members
  for select using (
    user_id = auth.uid()
    or lower(user_login) = lower(coalesce((auth.jwt() ->> 'email'), ''))
    or public.can_read_business(business_id)
  );

-- ----------------------------------------------------------------
-- books
-- ----------------------------------------------------------------
create table if not exists public.app_books (
  id               text primary key,
  business_id      text not null references public.app_businesses(id) on delete cascade,
  name             text not null,
  created_at_local text,
  deleted_at       timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index if not exists app_books_biz_idx on public.app_books(business_id);
drop trigger if exists app_books_updated_at on public.app_books;
create trigger app_books_updated_at
  before update on public.app_books
  for each row execute function public.set_updated_at();
alter table public.app_books enable row level security;
drop policy if exists app_books_select on public.app_books;
drop policy if exists app_books_write on public.app_books;
create policy app_books_select on public.app_books
  for select using (public.can_read_business(business_id));
create policy app_books_write on public.app_books
  for all using (public.can_write_business(business_id))
        with check (public.can_write_business(business_id));

-- ----------------------------------------------------------------
-- account_groups
-- ----------------------------------------------------------------
create table if not exists public.app_account_groups (
  id            text primary key,
  business_id   text not null references public.app_businesses(id) on delete cascade,
  name          text not null,
  kind          text not null,
  sort_order    integer,
  deleted_at    timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists app_account_groups_biz_idx on public.app_account_groups(business_id);
drop trigger if exists app_account_groups_updated_at on public.app_account_groups;
create trigger app_account_groups_updated_at
  before update on public.app_account_groups
  for each row execute function public.set_updated_at();
alter table public.app_account_groups enable row level security;
drop policy if exists app_account_groups_select on public.app_account_groups;
drop policy if exists app_account_groups_write on public.app_account_groups;
create policy app_account_groups_select on public.app_account_groups
  for select using (public.can_read_business(business_id));
create policy app_account_groups_write on public.app_account_groups
  for all using (public.can_write_business(business_id))
        with check (public.can_write_business(business_id));

-- ----------------------------------------------------------------
-- cash_accounts
-- ----------------------------------------------------------------
create table if not exists public.app_cash_accounts (
  id               text primary key,
  business_id      text not null references public.app_businesses(id) on delete cascade,
  group_id         text,                                           -- nullable; orphans tolerated
  name             text not null,
  hidden           boolean not null default false,
  sort_order       integer,
  created_at_local text,
  deleted_at       timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index if not exists app_cash_accounts_biz_idx on public.app_cash_accounts(business_id);
drop trigger if exists app_cash_accounts_updated_at on public.app_cash_accounts;
create trigger app_cash_accounts_updated_at
  before update on public.app_cash_accounts
  for each row execute function public.set_updated_at();
alter table public.app_cash_accounts enable row level security;
drop policy if exists app_cash_accounts_select on public.app_cash_accounts;
drop policy if exists app_cash_accounts_write on public.app_cash_accounts;
create policy app_cash_accounts_select on public.app_cash_accounts
  for select using (public.can_read_business(business_id));
create policy app_cash_accounts_write on public.app_cash_accounts
  for all using (public.can_write_business(business_id))
        with check (public.can_write_business(business_id));

-- ----------------------------------------------------------------
-- parties
-- ----------------------------------------------------------------
create table if not exists public.app_parties (
  id               text primary key,
  business_id      text not null references public.app_businesses(id) on delete cascade,
  name             text not null,
  kind             text,
  sort_order       integer,
  created_at_local text,
  deleted_at       timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index if not exists app_parties_biz_idx on public.app_parties(business_id);
drop trigger if exists app_parties_updated_at on public.app_parties;
create trigger app_parties_updated_at
  before update on public.app_parties
  for each row execute function public.set_updated_at();
alter table public.app_parties enable row level security;
drop policy if exists app_parties_select on public.app_parties;
drop policy if exists app_parties_write on public.app_parties;
create policy app_parties_select on public.app_parties
  for select using (public.can_read_business(business_id));
create policy app_parties_write on public.app_parties
  for all using (public.can_write_business(business_id))
        with check (public.can_write_business(business_id));

-- ----------------------------------------------------------------
-- categories
-- ----------------------------------------------------------------
create table if not exists public.app_categories (
  id            text primary key,
  business_id   text not null references public.app_businesses(id) on delete cascade,
  name          text not null,
  sort_order    integer,
  deleted_at    timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists app_categories_biz_idx on public.app_categories(business_id);
drop trigger if exists app_categories_updated_at on public.app_categories;
create trigger app_categories_updated_at
  before update on public.app_categories
  for each row execute function public.set_updated_at();
alter table public.app_categories enable row level security;
drop policy if exists app_categories_select on public.app_categories;
drop policy if exists app_categories_write on public.app_categories;
create policy app_categories_select on public.app_categories
  for select using (public.can_read_business(business_id));
create policy app_categories_write on public.app_categories
  for all using (public.can_write_business(business_id))
        with check (public.can_write_business(business_id));

-- ----------------------------------------------------------------
-- entries — the big one. Indexed by book_id for fast reads.
-- ----------------------------------------------------------------
create table if not exists public.app_entries (
  id               text primary key,
  book_id          text not null references public.app_books(id) on delete cascade,
  business_id      text not null,                                  -- denormalised for RLS speed
  type             text not null check (type in ('in','out')),
  amount           numeric not null,
  entry_date       date not null,                                  -- the user-set date
  party            text,
  party_id         text,
  account_id       text,
  category         text,
  note             text,
  created_by       uuid,
  created_by_name  text,
  edited_by        uuid,
  edited_at        timestamptz,
  created_at_local bigint,
  deleted_at       timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index if not exists app_entries_book_idx on public.app_entries(book_id);
create index if not exists app_entries_biz_idx on public.app_entries(business_id);
create index if not exists app_entries_date_idx on public.app_entries(business_id, entry_date desc);
drop trigger if exists app_entries_updated_at on public.app_entries;
create trigger app_entries_updated_at
  before update on public.app_entries
  for each row execute function public.set_updated_at();
alter table public.app_entries enable row level security;
drop policy if exists app_entries_select on public.app_entries;
drop policy if exists app_entries_write on public.app_entries;
create policy app_entries_select on public.app_entries
  for select using (public.can_read_business(business_id));
-- Staff edit-own enforcement happens in app code; DB allows any team writer.
create policy app_entries_write on public.app_entries
  for all using (public.can_write_business(business_id))
        with check (public.can_write_business(business_id));

-- ----------------------------------------------------------------
-- audit_expenses (owner-only in app; DB allows any team writer
-- but app code gates this to owner via canSeeAudit())
-- ----------------------------------------------------------------
create table if not exists public.app_audit_expenses (
  id               text primary key,
  business_id      text not null references public.app_businesses(id) on delete cascade,
  month            text not null,                                  -- 'YYYY-MM'
  description      text not null,
  amount           numeric not null,
  created_at_local bigint,
  edited_at_local  bigint,
  deleted_at       timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index if not exists app_audit_expenses_biz_idx on public.app_audit_expenses(business_id, month);
drop trigger if exists app_audit_expenses_updated_at on public.app_audit_expenses;
create trigger app_audit_expenses_updated_at
  before update on public.app_audit_expenses
  for each row execute function public.set_updated_at();
alter table public.app_audit_expenses enable row level security;
drop policy if exists app_audit_expenses_select on public.app_audit_expenses;
drop policy if exists app_audit_expenses_write on public.app_audit_expenses;
-- Owner-only in app; we still gate at DB to owner of the business.
create policy app_audit_expenses_select on public.app_audit_expenses
  for select using (
    exists (
      select 1 from public.app_businesses b
      where b.id = business_id and b.owner_id = auth.uid()
    )
  );
create policy app_audit_expenses_write on public.app_audit_expenses
  for all using (
    exists (
      select 1 from public.app_businesses b
      where b.id = business_id and b.owner_id = auth.uid()
    )
  ) with check (
    exists (
      select 1 from public.app_businesses b
      where b.id = business_id and b.owner_id = auth.uid()
    )
  );

-- ============================================================
-- Done. After running this:
--   1. In Supabase Dashboard → Database → Replication, enable the
--      "supabase_realtime" publication for the tables you want to
--      subscribe to (we'll do this in Stage 2):
--      app_entries, app_parties, app_categories, app_cash_accounts,
--      app_account_groups, app_businesses, app_books, app_members,
--      app_audit_expenses.
--   2. Test with the Hisabs "Test connection" button.
-- ============================================================
