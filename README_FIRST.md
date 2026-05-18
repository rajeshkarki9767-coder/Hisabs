# Hisabs v89.6.2 — schema-corrected release

```
index.html: e31cb4b6b72e0d0b28f512f9dfd51355
```

## Why this exists

You ran the diagnostic queries and they revealed my v89.6 SQL had
two assumptions wrong:

1. **IDs are TEXT, not UUID.** Your schema uses text IDs (from `uid()`),
   not Postgres UUIDs. The FK references would have failed.
2. **No `sort_order` column** in your existing dist-adjacent table
   (`app_audit_expenses`). I matched its pattern instead.
3. **RLS pattern uses `user_is_business_member()` helper** for SELECT,
   not an inline JOIN. Cleaner and matches what you've already tested.

The corrected SQL is in `sql/v89.6.2_distribution_sync.sql`. It:

- Uses `TEXT PRIMARY KEY` for the new tables
- Uses `TEXT REFERENCES app_businesses(id)` for FKs
- Stores `created_at_local` as TEXT (matches your existing convention)
- Uses your existing `user_is_business_member()` helper for SELECT
- Uses `owner_id = auth.uid()` for INSERT/UPDATE/DELETE (matches
  your existing app_businesses pattern)
- Has 4 separate policies per table (SELECT/INSERT/UPDATE/DELETE)
  matching your app_businesses style

The client code was also patched to remove `sort_order` from the
toDb/fromDb mappings, otherwise every write would fail with
"column sort_order does not exist".

## Deploy order

1. **Run the corrected SQL** (`sql/v89.6.2_distribution_sync.sql`)
   in Supabase SQL Editor

   If you tried running my v89.6 SQL earlier and got an error,
   nothing was committed (BEGIN/COMMIT block). Safe to run the
   new one.

2. **Verify** with the queries at the bottom of the SQL file.
   You should see:
   - 3 new tables created
   - 12 policies (4 per table)
   - 3 publication entries

3. **Replace index.html** and deploy:
   ```bash
   cd ~/Documents/GitHub/hisabs
   cp ~/Downloads/hisabs_v89_6_2/index.html ./index.html
   md5sum index.html
   # expected: e31cb4b6b72e0d0b28f512f9dfd51355
   ```

4. Commit + push.

## Cumulative changes from v89.0 → v89.6.2

| Version | Changes |
|---|---|
| v89.1 | Leak text fix, double-tap entries, long-press removed |
| v89.2 | Bottom modal buttons, audio fix |
| v89.3 | Floating button, anywhere swipe, modal icons |
| v89.4 | FAB center, invoice HWM, tax glitch, split preview, save buttons |
| v89.5 | Party UX, distribution glitch v1, Shift+Enter, chart tap, bigger mobile charts |
| v89.5.1 | Dead CSS cleanup |
| v89.6 | Distribution sync (had SQL/client bugs) |
| v89.6.1 | Resize-keyboard glitch fix (the REAL keyboard glitch root cause) + orphan function fix |
| v89.6.2 | **THIS RELEASE** — schema-matched SQL + sort_order removed from client |

## Smoke tests

After the SQL runs and code deploys:

1. **% prefix on Party input** ✓
2. **Distribution keyboard stays open on mobile** ← the resize-keyboard fix
3. **Owner edits → manager sees them on a different device** ← the actual sync working

## ⚠ Still outstanding

- Server-side invoice number reuse on delete (see V89_4_NOTES.md)

