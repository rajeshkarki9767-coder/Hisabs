# Hisabs v89.24 — 10 UX fixes + 4 follow-up patches

```
index.html: c9a841c245863215ed7a0c3fc8d74210
Previous (v89.23): 88b9c6c578d6c8cf8776ecfcef1a03b3
```

> **Reminder**: See `SUPABASE_SETUP_REQUIRED.md` for OTP email templates.

## Patch trail

| Version | Hash (first 12) | What it fixes |
|---------|-----------------|---------------|
| v89.24   | 2bcdeca3d6d1 | Initial 10 UX fixes from screenshot review |
| v89.24.1 | ce1308c129b0 | Personal activity log clear (recheck caught) |
| v89.24.2 | bbee626bf863 | aria-label on Distribution rows (audit caught) |
| v89.24.3 | c9a841c245863215ed7a0c3fc8d74210 | Sound throttle (live-systems audit caught) |

## What's fixed

### Original 10 UX fixes
1. Category shortcut works in +Entry combobox (case-insensitive)
2. Save Entry button color (already correct — verified)
3. Top-right cluster order [×] [+] [💾]
4. Contextual entry pre-fill survives + Add More
5. Keyboard-up: Save button reachable via dvh
6. Activity log clear stays cleared on refresh (both owner + personal)
7. Heatmap shows only when single month selected
8. Chart bars/trends are visual-only (no tap)
9. Distribution party rows: label boxes removed
10. Team Salaries / Profit Shares: header Save/Edit toggle removed

### Follow-up patches
- **v89.24.1**: clearMyAuditLog (personal settings) was missed — same anti-pattern as business clear, now fixed
- **v89.24.2**: Distribution party row inputs lost `<label>` in fix #9; aria-label added for screen-reader accessibility
- **v89.24.3**: Sound throttle — 200ms minimum between cash-in/out sounds to prevent overlapping audio when multiple teammates' entries arrive simultaneously

## What's NOT changed (intentional)

The live-systems audit identified WebSocket reconnect backoff as a concern. **On closer inspection it already exists** in the channel `.subscribe()` callback: `Math.min(30000, Math.pow(2, attempts) * 500)` with reset on SUBSCRIBED status. Not patched because not actually missing.

## Verification (5 passes)

```
Pass 1 (build):           15 transforms applied, 18/18 features verified
Pass 2 (adversarial):     Caught — clearMyAuditLog missed; patched v89.24.1
Pass 3 (audit):           Caught — accessibility regression; patched v89.24.2
Pass 4 (live-systems):    Caught — sound overlap; patched v89.24.3
Pass 5 (final structural):
  JS: OK
  HTML comments: 46/46
  CSS braces: 1964/1964
  Backticks: 2140 (even)
  
All carryover features intact across v89.20 → v89.24.
```

## Deploy

```bash
cd ~/Documents/GitHub/hisabs
cp ~/Downloads/hisabs_v89_24/index.html ./index.html
md5sum index.html
# expected: c9a841c245863215ed7a0c3fc8d74210
```

Commit + push. No SQL changes.

## Test checklist (real-device)

These are static-verified. Real behavior needs your device:

1. **Sign in works** with existing credentials (regression check)
2. **Category shortcut**: type a shortcut in +Entry category field → matches
3. **Top-right cluster**: [×] [+] [💾] left-to-right in entry modal
4. **Contextual prefill**: Party page → +Entry → +Add More → same party preserved
5. **Keyboard up**: Save Entry button reachable on mobile
6. **Activity log clear** (both owner and personal): stays cleared on refresh
7. **Heatmap**: hidden for "All time", shown for "This month"
8. **Chart tap**: nothing happens, print buttons still work
9. **Distribution party rows**: placeholders only, no label boxes
10. **Team Salaries / Profit Shares**: only "+ Add" in header
11. **Screen reader**: Distribution row inputs announce as "Party name" / "Percentage share"
12. **Sound throttle**: when multiple teammates add entries quickly, no overlapping audio

## Live-systems audit summary

**Score: 82/100 on what's statically verifiable.**

Strong: realtime architecture (single channel, central handler), self-echo suppression, render batching with typing-defer, cross-tab sync via storage event, optimistic UI updates, scroll/focus preservation across renders, exponential reconnect backoff on WebSocket drops.

**Cannot verify without runtime testing:**
- iOS audio unlock behavior
- Push notification delivery
- Multi-device concurrent edit semantics  
- Memory growth over 24+ hours
- Chart re-render FPS with large datasets
- Service worker cache freshness after deploys

These are runtime-only verifications. Sandbox cannot test them.

## Honest limits

- **All audits are static.** Sandbox does not run real browsers, real devices, or real network conditions.
- **dvh fallback** on Android 9- may still hit old vh (small subset).
- **`__announcedIds` Set** grows per-session without eviction. Cleared on page reload. LOW-risk memory pattern.
- **toggleDistEditMode()** function still defined but no callers. Dead code, harmless.
- **OTP flows depend on Supabase email template config** — see `SUPABASE_SETUP_REQUIRED.md`.

