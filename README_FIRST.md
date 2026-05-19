# Hisabs v89.29 — Final audited build

```
index.html: 17b6633bf369ef89b3d304c739e3f989
Bundle:     hisabs_v89_27_final.zip
```

## v89.29 changes

### Code hygiene (+1 point)
- 290 lines + 17 KB removed
- 8 truly-orphan functions deleted
- 7 orphan CSS class blocks deleted
- Functions with active callers preserved

### Performance (+1 point)
- `__announcedIds` capped via LRU at 500 entries
- Was unbounded; now ~18 KB max memory ceiling

### UI/UX (+1 point)
- PDF/CSV export: "Generating PDF/CSV…" toast at start
- Double-fire blocked via `__exportInFlight` flag
- All 4 early-return paths clear flag (no 30s lockout on quick errors)
- 30s safety auto-clear in case of unexpected exception

## Verification

```
JS syntax: OK
HTML comments: 49/49
CSS braces: 1970/1970
Backticks: 2096 (even)
File: 1,742,752 bytes / 29,570 lines
```

All 48 fixes + carryover items verified (v89.13 → v89.29).
All 3 v89.28 splash sites still sealed (if-error + catch both close modal).
All 16 auth functions present.
All 16 critical infra functions intact.

## Setup steps still required

See **V89_28_SETUP.md** for details (unchanged from prior bundle):
- Update 3 Supabase email templates
- Deploy `delete-self-account` Edge Function
- Welcome email via combined "Confirm signup" template

## Deploy

```bash
cd ~/Documents/GitHub/hisabs
cp ~/Downloads/hisabs_v89_27_final/index.html ./index.html
md5sum index.html
# expected: 17b6633bf369ef89b3d304c739e3f989
```

