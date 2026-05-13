# Supabase setup for Hisabs

Hisabs uses one Supabase table — `backups` — plus Supabase Auth. This document is the canonical reference for the schema and configuration. If "Test connection" in Settings → Data fails, start here.

## Table SQL

Paste this into Supabase Dashboard → SQL Editor → New query, then **Run**:

```sql
-- backups: one rolling snapshot per (user_id, label) of the full Hisabs data.
create table if not exists public.backups (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  label        text not null default 'latest',
  payload      jsonb not null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (user_id, label)
);

-- Index for fast lookup by user
create index if not exists backups_user_id_idx on public.backups(user_id);

-- Row-Level Security: a user can only touch their own rows.
alter table public.backups enable row level security;

-- Clear any old policies (in case the table existed with different policy names)
drop policy if exists "backups_select_own" on public.backups;
drop policy if exists "backups_insert_own" on public.backups;
drop policy if exists "backups_update_own" on public.backups;
drop policy if exists "backups_delete_own" on public.backups;

create policy "backups_select_own"
  on public.backups for select
  using (auth.uid() = user_id);

create policy "backups_insert_own"
  on public.backups for insert
  with check (auth.uid() = user_id);

create policy "backups_update_own"
  on public.backups for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "backups_delete_own"
  on public.backups for delete
  using (auth.uid() = user_id);
```

The app code in Hisabs is **schema-tolerant** — if the `label` column is missing, it falls back to most-recent-by-`updated_at`. If the unique constraint is missing, it falls back to delete-then-insert. But running the SQL above gives you the clean path.

## Authentication settings

Supabase Dashboard → Authentication → **URL Configuration**:

- **Site URL**: your deployed app URL (e.g. `https://hisabs.vercel.app`). This is where password-reset emails redirect the user back to.
- **Redirect URLs**: add each environment you test from, e.g. `http://localhost:8765`, `http://localhost:3000`, plus your production URL.

Supabase Dashboard → Authentication → **Email**:

- For prototype simplicity: **disable "Confirm email"** so new sign-ups can use the app immediately.
- For production: enable it (users will receive a confirm-email link before they can sign in).

## Auth providers

Currently Hisabs uses email + password only. If you want Google sign-in:

1. Authentication → Providers → Google → enable
2. Add your Google OAuth client ID and secret (from Google Cloud Console)
3. In Hisabs code, re-add a "Continue with Google" button that calls `sb().auth.signInWithOAuth({ provider: 'google' })`

Not done in this version because it requires a Google Cloud project and isn't trivial to provision automatically.

## Testing the wiring

Once deployed:

1. Sign in to Hisabs with a real cloud account.
2. Open Settings → Data → Cloud sync → click **"Test connection"**.
3. You should see four ✓ lines:
   - SDK loaded
   - Project endpoint reachable
   - Signed in as your@email.com
   - backups table readable (N rows)

If any line shows ✗, it tells you exactly what's wrong.

## Costs

Supabase free tier: 50 MAU, 500MB DB, 5GB bandwidth, 1GB storage. For Hisabs's single-user use the free tier is more than enough.
