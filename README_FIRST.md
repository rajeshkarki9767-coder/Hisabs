# Hisabs v89.5.1 — full deploy bundle

This is the cumulative rollup of every change since v89.0
(currently live at hisabs.vercel.app).

## File hashes

```
index.html  → f6c73e214ec1f91267213eceb96c542a   (v89.5.1)
```

Currently live (v89.0): `226f6892ed9b50c57658ce22d3bfdc8c`

## Folder structure

```
hisabs_v89_5_1/
├── README_FIRST.md       ← you are here (don't commit)
├── V89_NOTES.md          ← original v89 release notes + deploy guide
├── V89_1_QA.md           ← v89.1 static QA report
├── V89_4_NOTES.md        ← v89.4 notes incl. server-side invoice SQL
├── .gitignore            ← matches what's already in your repo
├── index.html            ← v89.5.1, REPLACES your existing one
├── vercel.json           ← REPLACES your existing one (your CSP + crons)
└── api/
    └── cron/
        └── digest.js     ← Vercel cron edge function
```

## What's cumulative in this build (since v89.0)

| Version | Changes |
|---|---|
| v89.1 | Fixed leaked dev text at bottom of pages. Chart long-press scrub removed. Entry rows use double-tap (was long-press). |
| v89.2 | Bottom modal buttons restored. Audio playback fixed (was hanging on data:URI mp3). HTML5 audio unlock on first gesture. |
| v89.3 | Floating +Entry restored. Anywhere-swipe-right opens sidebar. Modal save = floppy disk icon. |
| v89.4 | FAB bottom-center. Invoice HWM (no number reuse on delete). Audit tax keyboard glitch fixed. Split preview always shown. Currency+rate save button. |
| v89.5 | Party "Rajesh" placeholder removed. Party rows stacked layout. Parties always editable. Distribution keyboard glitch fixed. Shift+Enter for Add More. Chart tap = tooltip only (no full modal). Bigger mobile charts. |
| v89.5.1 | Removed 1 line of dead CSS left over from v89.5. No behavior change. |

## What's NOT in this zip

- **package.json / package-lock.json** — you already have these from
  `npm install web-push` during the v89.0 deploy. Don't replace them.
- **Your existing repo files** (vendor/supabase.umd.js, manifest.webmanifest,
  sw.js, icons/, screenshots/, PRIVACY.html, etc.) — those stay as-is.
  Only the 4 files above get touched.

## Deploy steps

```bash
cd ~/Documents/GitHub/hisabs

# Drop the new files in (preserves your other files)
cp ~/Downloads/hisabs_v89_5_1/index.html ./index.html
cp ~/Downloads/hisabs_v89_5_1/vercel.json ./vercel.json
mkdir -p api/cron
cp ~/Downloads/hisabs_v89_5_1/api/cron/digest.js ./api/cron/digest.js

# Verify the hash
md5sum index.html
# expected: f6c73e214ec1f91267213eceb96c542a

# Look at what's about to commit
git status
```

Then in GitHub Desktop:

**Summary:**
```
v89.5.1: cumulative 6 patches over v89 — modal UX, audio, distribution glitch, charts, dead-CSS cleanup
```

Click **Commit** then **Push origin**.

Wait for Vercel green, then test on phone (hard refresh, not the installed PWA first).

## Smoke tests after deploy

1. **Bottom of every page** — that ugly "entry modal picks In vs Out..." text gone ✓
2. **Floating +Entry button** — bottom-CENTER of viewport, scrolls with page? ✓
3. **Distribution keyboard** — type in Party Name / %, Currency, Rate, Salary → keyboard stays open, no glitch ✓
4. **Audio** — tap screen once first, then save entry → hear cash-in MP3 ✓
5. **Chart tap** — tap a bar → small tooltip with value + date appears briefly, no full-screen modal ✓
6. **Charts on mobile bigger** — taller, more readable text ✓
7. **Shift+Enter on desktop** in +Entry modal → fires Add More ✓
8. **Invoice number on delete** — delete the latest entry, tap +Entry → number is NOT reused ✓
9. **Audit Tax** — tap tax %, keyboard stays open, type, Save without glitch ✓
10. **Anywhere swipe right** opens sidebar; vertical scroll does NOT accidentally trigger ✓

## ⚠ One known gap — server-side invoice numbering

The client preview is fixed in v89.4. The actual database trigger that
assigns invoice numbers on the server may still reuse deleted numbers.
See V89_4_NOTES.md for the SQL fix you'd need to deploy separately.
Not blocking — the visible UI looks right; only affects long-term data
integrity.
