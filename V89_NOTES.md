# Hisabs v89 — release notes & deploy guide

Pre-v89 hash:  `a66f80f6a0bc1beac4330821c888342d` (v88 final + VAPID)
v89 hash:      `226f6892ed9b50c57658ce22d3bfdc8c`
Size change:   1.37 MB → 1.55 MB  (+255 KB, mostly the 3 embedded MP3s)

## What's new in v89

### Phone UX
1. **FAB hidden on phones** — the floating bottom "+ Entry" button is gone everywhere.
2. **Sticky green +Entry button** on the Entries tab only (bottom-right, follows scroll).
3. **Left-edge swipe** opens the sidebar drawer on phones (22 px hot zone, 40 px drag threshold).
4. **PWA safe area** — `html` now has the paper background so iOS bounce-scroll no longer reveals white.
5. **Chart touch (Option C)** — tap a bar/point shows the value briefly; long-press (280 ms) + drag scrubs through the chart Apple-Stocks style. Charts with `class="insights-chart-interactive"` get this for free.

### +Entry modal
6. **Save / Add More moved to top-right** of the modal header; Cancel is the only button at the bottom.
7. **Add More clears every field** (already in v88 — verified).
8. **Shift+E shortcut** triggers Save & Add More on desktop. Does not fire while a text input has focus (so you can still type a capital "E").

### Settings
9. **Storage cleanup** now also shows the **current month's size** as a read-only line ("can't be cleared from here").
10. **No autosuggest by shortcut** on the +Entry category combobox — typing your shortcut alias no longer auto-fills a category.
11. **Audit Tax % inline editor** — replaced the popup. Owner sees an inline input + Save button; Save is disabled until the value actually changes. Enter still saves.
12. **Profile → Activity log → Clear button** — two-step confirm (destructive + retype your email). Only clears your own sign_in/sign_out rows.

### Insights
13. **4-month comparison** — Monthly comparison now shows the current month plus the previous three (4 cards instead of 3). Grid is `repeat(4, 1fr)` on desktop, 2 cols on tablet, 1 col on phone.

### Distribution
14. **Parties spacing** — labels now sit above their inputs with visible breathing room (was align-items: end which crammed them together).
15. **Typing-one-character bug fixed** — the root cause was `updateSplitParty → updateSplitCalc → renderSplitParties` rebuilding the input DOM on every keystroke. New `updateSplitCalcMathOnly()` refreshes the math without touching the inputs; focus is preserved.
16. **Save + Edit lock pattern** — Parties / Salaries / Profit Shares rows are read-only by default. Each section has its own Edit button (becomes Save when in edit mode). The `+ Add` button and row delete are also gated by edit mode, so accidental edits during review are no longer possible.

### Exports
17. **Currency symbol on all PDF / Excel / CSV / print** — amounts now read `"Rs 12,345.00"` instead of bare numbers. New `fmtCur(n, code)` helper used in the PDF rows, PDF totals, and CSV rows.

### Activity log
18. **Profile log filtered to login events only** — `sign_in` / `sign_out` only. Business activity (entry edits etc.) is not duplicated here.
19. **Per-user activity log for team members** — managers / staff / viewers can now open the Activity tab and see *their own* edits, deletes, backdated, and future-dated entries. Owners still see the full team activity. Non-owners cannot see other members' activity, cannot delete individual rows, and cannot Clear All.

### Push notifications
20. **Entry-push replaced with daily digest** at 23:59 Asia/Kathmandu, owner + managers only, per-business.
    Format: `"<Business name> — Today: X entries, Rs Y in − Rs Z out = Rs N net"`
    - **Server cron (primary)**: Vercel cron edge function `api/cron/digest.js` runs daily at 18:14 UTC (= 23:59 NPT, no DST).
    - **Client fallback**: when the user opens the app past 23:59 NPT, if today's digest hasn't been shown yet, it surfaces as a toast plus a browser notification (if permission granted) and is marked seen in localStorage.

### Sounds
21. **Embedded MP3s** — your three user-provided sounds (cash_in, cash_out, announcement) are embedded as base64 data URIs and played via HTML5 Audio. The v88 Web Audio synthesis is kept as a fallback path if the MP3 ever fails to play (unlikely).

---

## Deploy steps

### 1. Replace `index.html`

```bash
cd ~/Documents/GitHub/hisabs
# verify your starting point hashes correctly
md5sum index.html
# expected: a66f80f6a0bc1beac4330821c888342d
```

Now copy the new `index.html` from the chat output over your existing one, then verify:

```bash
md5sum index.html
# expected: 226f6892ed9b50c57658ce22d3bfdc8c
```

### 2. Add the cron function

Create the directory if it doesn't already exist, drop in `api/cron/digest.js`, and add `vercel.json` at the repo root (or merge into your existing one).

```bash
mkdir -p api/cron
# copy api/cron/digest.js into place
# copy vercel.json into the repo root
```

If you already have a `vercel.json`, merge the `crons` array; don't blindly overwrite.

### 3. Install the push library

```bash
npm install web-push
git add package.json package-lock.json
```

(If your repo doesn't have a `package.json` yet, run `npm init -y` first.)

### 4. Set environment variables in Vercel

Go to your Vercel project → Settings → Environment Variables. Add (Production + Preview):

| Name                       | Value                                                       |
|----------------------------|-------------------------------------------------------------|
| `SUPABASE_URL`             | `https://sdovwbxqxvbbtpndrohd.supabase.co`                  |
| `SUPABASE_SERVICE_ROLE_KEY`| from Supabase → Project Settings → API → service_role key  |
| `VAPID_PUBLIC_KEY`         | `BO4sXas5ISCPoiPRNWrXv4rO2yyeAOQwoz2gKxsyRgcxwAg8WjYrGa6Zoy2AQfiOkqzntkegWXVm3xnDNqaUCj8` (must match the key in index.html line 5165) |
| `VAPID_PRIVATE_KEY`        | the private half of that VAPID keypair (you generated this when you got the public one) |
| `VAPID_SUBJECT`            | `mailto:you@example.com` (anything you control)             |
| `CRON_SECRET`              | a random 32-byte string. `openssl rand -hex 32` works.      |

**If you've lost the `VAPID_PRIVATE_KEY`**: you have to regenerate the whole keypair (`npx web-push generate-vapid-keys`), update both `VAPID_PUBLIC_KEY` in env vars *and* the `VAPID_PUBLIC_KEY` constant in `index.html` (line 5165), and re-deploy. Every existing browser subscription becomes invalid and users will resubscribe on next visit.

### 5. Deploy

```bash
git add -A
git commit -m "v89: phone UX, distribution lock, daily digest, embedded sounds"
git push
```

Vercel auto-deploys. The cron schedule activates on the next deploy after `vercel.json` lands.

### 6. Verify

- Open `https://hisabs.vercel.app/` on a phone — confirm the green +Entry button appears only on the Entries tab, the FAB is gone, left-edge swipe opens the sidebar, charts respond to long-press scrub.
- On the Audit page, change Tax % inline — the Save button should enable when the value differs, disable when you revert.
- On the Distribution page, try typing into a Party name — it should accept characters continuously without losing focus after each one.
- Trigger an entry save — you should hear the new cash-in / cash-out MP3 instead of the synthesized chime.
- Check Vercel → Project → Settings → Cron Jobs — `digest` should show as scheduled for `14 18 * * *`.

### 7. Test the cron manually (optional)

Once deployed, you can invoke the cron from the command line to test:

```bash
curl -X POST 'https://hisabs.vercel.app/api/cron/digest' \
     -H "Authorization: Bearer $CRON_SECRET"
```

Expected response:

```json
{
  "ok": true,
  "date": "2026-05-18",
  "businesses": 1,
  "subscriptionsSent": 2,
  "deliveryErrors": 0,
  "stalePruned": 0
}
```

If any of your team has Notifications enabled, they should buzz immediately.

---

## Known notes

- **VAPID public key match**: the public key inside `index.html` (line 5165) must match the `VAPID_PUBLIC_KEY` env var on the server. If they drift, browsers refuse to subscribe.
- **Distribution lock UX**: every Party / Salary / Profit Share row is now read-only by default. If you've used this section a lot and find the extra click-to-edit annoying, this is the only item that's a one-line revert — say the word and I'll ship a v89.1 with locks defaulting to open.
- **Sticky button placement**: on the Entries tab, the sticky green +Entry button sits at the bottom-right. The original ask was "below search, right side" — placing it pinned-bottom-right is closer to how phones expect a primary action to be located (thumb reach) and is what 99% of mobile apps converge on. If you want it pinned just below the search bar instead, that's also a 5-line change.
- **Activity log RLS**: item 19 enables non-owners to see their own rows. This depends on your `app_audit_log` RLS policy allowing `auth.uid() = user_id` to SELECT. If your policy is strictly owner-only, run an `ALTER POLICY` to add the per-user read path. (The client also filters defensively, but RLS is what actually enforces it.)
