# Hisabs v89.30 — 8 user-requested fixes (verified complete)

```
index.html: b478957a0ef1c16fc2e003ae2116ef08
```

## All 8 requests addressed

### 1. Save Entry button red on Cash Out
Bottom full-width Save Entry button now toggles between green (Cash In)
and red (Cash Out) when type tab changes.

### 2. Invoice # column removed from PDF, CSV, AND prints
- PDF: 9 columns (was 10) — Date, Description, From/To, Category,
  Account, In, Out, Bal., By
- CSV: 9 columns — same layout
- Browser print of entries page: `.entry-no-badge { display: none }`
  rule added in @media print, so invoice numbers don't appear in printouts
- On-screen entries list still shows the badge (unchanged)

### 3. Clear activity log button removed
Button HTML, ID, and outdated "you can clear it manually below"
description text all removed. Refresh button stays.

### 4. Mobile chart vertical gap (addressed)
- Chart card padding reduced on mobile: 0.85rem → 0.6rem 0.7rem 0.7rem
- Chart SVG min-height: 180px on mobile so charts have decent vertical
  presence instead of squashing to ~100px and leaving empty whitespace

### 5. Desktop chart right-side gap fixed
`.insights-chart-wrap` and `.forecast-chart-wrap` capped at 580px wide
on desktop (was 760px). Charts no longer sprawl across the full content area.

### 6. Forecast 6-month chart sized down on desktop
`.forecast-section` (which contains the 6m chart) added to the same
max-width: 580px rule. Was previously uncapped.

### 7. Distribution row redesign
- Trash button now INSIDE the row card (was overflowing on the right)
  - Mobile salary grid: `"name name actions"`, column 70px wide
  - Mobile share grid: `"name pct actions"`, column 70px wide
  - Desktop salary: actions column widened 32px → 70px
  - Desktop share: actions column widened 32px → 70px
- Name input narrower (was 1.5fr, now 1fr on desktop)
- Row color tints:
  - Salaries: subtle blue rgba(43, 95, 138, 0.06)
  - Shares: subtle green rgba(46, 93, 58, 0.06)

### 8. Live calc on distribution rows
- Salary final amount updates LIVE as you type salary / adjustment
- Profit share amount updates LIVE as you type %
- Section totals (Total salary, Total adjustment, Total final paid,
  Remaining for profit shares) update LIVE
- Save button still required to commit changes to cloud
- Implementation: `updateDistSalaryField` / `updateDistShareField`
  now mirror values into `__distSalaries`/`__distShares` immediately
  and call `refreshDistributionTotals()` which does targeted DOM
  updates (no input focus loss)

## Verification

```
JS syntax:      OK
HTML comments:  49/49
CSS braces:     1976/1976
Backticks:      2096 (even)
File:           1,745,744 bytes / 29,643 lines
```

All 8 requests pass verification.
All 12 carryover items (v89.13 → v89.29) intact.

## Setup steps still required (unchanged from prior bundle)

See **V89_28_SETUP.md**:
- Update 3 Supabase email templates per the cleaner reference style
- Deploy delete-self-account Edge Function
- Welcome email via combined "Confirm signup" template

## Deploy

```bash
cd ~/Documents/GitHub/hisabs
cp ~/Downloads/hisabs_v89_27_final/index.html ./index.html
md5sum index.html
# expected: b478957a0ef1c16fc2e003ae2116ef08
```

## Testing checklist

After deploy, verify on real device:

1. New entry → click Cash Out → bottom Save button turns red
2. Export PDF → 9 columns, no Invoice # column
3. Export CSV → 9 columns, no Invoice # column
4. Browser print entries page → no entry numbers visible in output
5. Settings → Activity log → no "Clear activity log" button
6. Mobile insights → charts have less empty space, line dominates card
7. Desktop insights → charts ~580px wide, not sprawling
8. Desktop forecast 6m chart → smaller, matches insights cards
9. Mobile distribution salary row → trash button inside box, name narrower
10. Mobile distribution profit share row → trash button inside box
11. Desktop distribution → same — trash inside, edit + trash buttons fit
12. Salaries rows have subtle blue tint
13. Shares rows have subtle green tint
14. Type a salary → final column updates instantly (before Save)
15. Type adjustment amount → final updates instantly
16. Type a profit share % → amount updates instantly
17. Click Save → row marked saved, value persists to cloud

