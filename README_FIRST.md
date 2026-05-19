# Hisabs v89.30.1 — desktop chart width fix

```
index.html: 7174d13bc3a1f2ab7a8f9c7544f106e7
```

## What changed from v89.30

### Desktop chart width cap REMOVED

In v89.30 I capped desktop chart cards at `max-width: 580px`. On wide
monitors (laptop/desktop) this made charts feel cramped on the left and
left huge empty whitespace on the right side of the card.

v89.30.1 removes the cap entirely. Chart cards now span the natural
content width on desktop, which matches the surrounding cards.

This affects:
- Insights: Daily cash flow, Daily Net Profit Graph, Cash flow by month,
  Net Profit Graph by Months, Cumulative profit
- Forecast: 6-month operating profit trend

Mobile rules unchanged — chart cards still use tighter padding
(0.6rem 0.7rem 0.7rem) and min-height: 180px on mobile from v89.30.

### About the "right-side gap" issue

The original user complaint of "huge gap on right side of the graph"
was actually about sparse data on the chart x-axis (e.g., May data
only on days 14-19 of 31), not container sprawl. The chart canvas
correctly shows the full month range, with data clustered where it
exists. This is correct behavior — capping the container width doesn't
help and actually hurts visual proportion.

If you'd prefer the chart to zoom to the data range only (showing only
the days/months that have data), that's a different feature request
involving chart logic changes, not container CSS.

## All previous fixes preserved

All 41 fixes from v89.13 through v89.30 verified intact, including
all 8 v89.30 user-requested fixes:

1. Save Entry button red on Cash Out tab ✓
2. Invoice # removed from PDF/CSV/print ✓
3. Clear activity log button removed ✓
4. Mobile chart vertical gap fixed (tighter padding + min-height) ✓
5. ~~Desktop chart max-width 580px~~ → REMOVED in v89.30.1
6. ~~Forecast 6m chart max-width~~ → REMOVED in v89.30.1
7. Distribution row redesign (trash inside, narrower name, color tints) ✓
8. Live calc on distribution rows ✓

Fixes 5 and 6 still apply but via removal of the cap, not reduction.
Charts on desktop now use the natural content width — which is what
"fitting properly" looks like on big monitors.

## Verification

```
JS syntax:      OK
HTML comments:  49/49 balanced
CSS braces:     1974/1974 balanced
Backticks:      2096 (even)
File:           1,746,062 bytes / 29,644 lines
```

## Setup steps still required (unchanged)

See **V89_28_SETUP.md**:
- 3 Supabase email templates
- delete-self-account Edge Function deploy

## Deploy

```bash
cd ~/Documents/GitHub/hisabs
cp ~/Downloads/hisabs_v89_27_final/index.html ./index.html
md5sum index.html
# expected: 7174d13bc3a1f2ab7a8f9c7544f106e7
git add . && git commit -m "v89.30.1: remove desktop chart max-width cap" && git push
```

