# Hisabs v89.4 — release notes

**File:** `index.html`
**Hash:** `8af161b059032fadebb7fc1fd433015b`
**Previous:** v89.3 = `2edd80e2517d762d014935d893d7e5df`

## What changed in v89.4

1. **Floating +Entry button** is now centered at the bottom of the screen (was bottom-right in v89.3)
2. **Invoice numbering** doesn't reuse deleted numbers — the *preview* in the +Entry modal will now correctly show #8 after #7 is deleted. **See the SQL note below — this needs a server-side fix too for the actual stored number.**
3. **Audit Tax % keyboard glitch** is fixed. Cause: tapping the tax input let the keyboard pop up, then a background re-render destroyed the input → keyboard collapsed → focus-restore re-opened it (the "glitch" you saw). Now: clicking Save doesn't re-render the whole page; and if a background re-render happens while you're typing, the focus is preserved synchronously instead of next-frame.
4. **Split & Convert "Add parties to see live preview"** message is now always visible
5. **Save button on Currency + Rate** with a "✓ Saved" confirmation flash (the values were already auto-saving on every keystroke; this adds the missing visible confirmation)

---

## ⚠ Important: server-side invoice number fix

**The change I just made is half a solution.**

In your app:
- The **preview number** shown in the +Entry modal — comes from the client (`nextEntryNoFor`). ✅ v89.4 fixes this with a localStorage high-water-mark.
- The **actual stored number** on the row in Supabase — comes from a **database trigger** that fires on INSERT. I cannot see your SQL from this sandbox, so I don't know what algorithm it uses.

If the database trigger uses `MAX(entry_no) + 1` from existing rows (which is the obvious naive approach), **deleting #7 will still cause the next insert to reuse #7 on the server side, even though the client preview correctly showed #8.** Then a sync would overwrite the client value back to #7.

You need to check your trigger. Run this in the Supabase SQL editor to see it:

```sql
SELECT pg_get_functiondef(p.oid)
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE p.proname ILIKE '%entry_no%' OR p.proname ILIKE '%assign%entry%';
```

It'll print the function source. If you see something like `SELECT COALESCE(MAX(entry_no), 0) + 1 FROM entries WHERE ...` — that's the bug.

**Fix:** add a separate table that tracks the high-water-mark per (book_id, year_month), and have the trigger use that instead of MAX. Roughly:

```sql
-- 1. Create the HWM table
CREATE TABLE IF NOT EXISTS book_entry_no_hwm (
    book_id  UUID NOT NULL,
    yyyymm   TEXT NOT NULL,
    hwm      INT  NOT NULL DEFAULT 0,
    PRIMARY KEY (book_id, yyyymm)
);

-- 2. Backfill from existing entries
INSERT INTO book_entry_no_hwm (book_id, yyyymm, hwm)
SELECT book_id, to_char(date::date, 'YYYY-MM'), MAX(entry_no)
FROM entries
WHERE entry_no IS NOT NULL
GROUP BY book_id, to_char(date::date, 'YYYY-MM')
ON CONFLICT (book_id, yyyymm) DO UPDATE
  SET hwm = GREATEST(book_entry_no_hwm.hwm, EXCLUDED.hwm);

-- 3. Replace the assign-entry-no trigger
CREATE OR REPLACE FUNCTION assign_entry_no()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    next_no INT;
    ymo     TEXT;
BEGIN
    IF NEW.entry_no IS NOT NULL THEN
        -- Caller is asserting the number (e.g. backfill); honor it but
        -- still bump the HWM so future inserts skip past it.
        ymo := to_char(NEW.date::date, 'YYYY-MM');
        INSERT INTO book_entry_no_hwm (book_id, yyyymm, hwm)
        VALUES (NEW.book_id, ymo, NEW.entry_no)
        ON CONFLICT (book_id, yyyymm) DO UPDATE
          SET hwm = GREATEST(book_entry_no_hwm.hwm, NEW.entry_no);
        RETURN NEW;
    END IF;

    ymo := to_char(NEW.date::date, 'YYYY-MM');

    -- Bump the HWM atomically and read the new value
    INSERT INTO book_entry_no_hwm (book_id, yyyymm, hwm)
    VALUES (NEW.book_id, ymo, 1)
    ON CONFLICT (book_id, yyyymm) DO UPDATE
      SET hwm = book_entry_no_hwm.hwm + 1
    RETURNING hwm INTO next_no;

    NEW.entry_no := next_no;
    RETURN NEW;
END;
$$;

-- 4. Make sure the trigger is wired up (name varies by your schema)
-- DROP TRIGGER IF EXISTS trg_assign_entry_no ON entries;
-- CREATE TRIGGER trg_assign_entry_no
--   BEFORE INSERT ON entries
--   FOR EACH ROW EXECUTE FUNCTION assign_entry_no();
```

**Important caveats:**
- I have not seen your actual `entries` table schema or your current trigger. The exact column names (`book_id`, `date`, `entry_no`) may differ. Adjust to match yours.
- The `book_entry_no_hwm` table needs RLS too — match the policies on `entries`.
- The trigger name (`trg_assign_entry_no`) and existing trigger source need to match. Don't blindly run the CREATE TRIGGER line — first find what's already there with the query above.
- Backup your DB before running this. Always.

**If you don't want to deal with this right now:** the client-side fix in v89.4 is enough for the preview number to look right in the UI. The server may still reuse numbers on the actual stored row, but you'd only see this if you compared the preview to the final saved badge after sync. For a daily-use app, the client fix is the visible part — the SQL fix is for data integrity over time.

---

## Deploy

Only `index.html` changes:

```bash
cd ~/Documents/GitHub/hisabs
mv ~/Downloads/index.html ./index.html
md5sum index.html
# expected: 8af161b059032fadebb7fc1fd433015b
```

Commit message:
```
v89.4: bottom-center FAB, invoice HWM, tax glitch fix, split preview always visible, currency/rate save
```

Then push.

## After deploy — test

1. **Floating button** — open Entries tab on phone. Button should sit in the **bottom-center** of the screen, not bottom-right.
2. **Invoice number after delete** — create 3 entries (they should be #N, #N+1, #N+2 in the current month). Delete #N+2. Tap +Entry. The preview should show #N+3, not #N+2.
3. **Tax % glitch** — open Audit, tap the Tax % input. Keyboard should open and stay open. Type a number — Save button enables. Click Save — should NOT cause a full page re-render or any flicker.
4. **Split preview** — go to Distribution. The "Add parties below to see a live preview." message should be visible from the start, even before you add any parties or set currency.
5. **Currency + Rate Save** — type something in Currency, click Save. A "✓ Saved" chip should flash next to the button for 1.8 seconds.

Tell me if any of these don't work as described, or if you see new issues.
