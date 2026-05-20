# Hisabs Changelog

All notable changes to Hisabs are documented here. Format roughly follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) but pragmatically — this is a single-developer project and the changelog is for orientation, not formal release management.

## Versioning

- **Major** (`v89.x`): the current generation. Single-file PWA built around Supabase + Vercel.
- **Minor** (`v89.31`): feature additions.
- **Patch** (`v89.31.x`): bug fixes and refinements within a feature.

The version is embedded in code comments throughout `index.html` (`// v89.31.2: ...`) for traceability. Deployed builds are identified by the md5 hash of `index.html`.

---

## [v89.31.2] — 2026-05-20

Risk-mitigation release. No new features; addresses production-readiness items flagged by the post-v89.31.1 audit.

### Added
- **Self-test suite** — `window.hisabsSelfTest()` callable from DevTools. Runs 34 pure-logic checks covering DOB validation, email/phone normalisation, birthday math, currency formatting, entry math, URL builders, meta building, sum aggregation, and permission helpers. Use `hisabsSelfTest({verbose:true})` for per-check output.

### Changed
- **Dark mode contact buttons** — Call / WhatsApp / Email buttons on the party detail page now have explicit `[data-theme="dark"]` overrides with lifted alpha and dark-appropriate text colours. Auto-theme (follow OS) also respects `prefers-color-scheme: dark`.
- **Scroll defer for renderAll** — added `__lastScrollAt` tracker hooked to `scroll`/`wheel`/`touchmove` (passive, capture). `_runRenderAllOrDeferIfTyping` now waits up to 250ms after the last scroll event before re-rendering. Targets the "scrolls up automatically while reading Insights" glitch caused by realtime/sync events firing mid-scroll.
- **Print fix hardened for cross-browser** — added both legacy (`page-break-*`) and modern (`break-*`) properties on the print overlay, cards, and a wildcard descendant rule. Added `max-height: 19cm` + `overflow: hidden` on the overlay as belt-and-suspenders. Targets browsers (older Safari, Firefox pre-67) that ignore one of the break properties.
- **Birthday banner timezone semantics** — clarifying comment added to `todayYmd()` explaining that birthday math is intentionally local-time across all four consumers (`isBirthdayBannerDismissedToday`, `partiesWithBirthdayToday`, `daysUntilBirthday`, `ageOnNextBirthday`). No behaviour change.

### Hash
`bafb9007359e31ada44f0370fb8fa200`

---

## [v89.31.1] — 2026-05-20

Three fixes layered on top of v89.31.0.

### Added
- **Top 15 parties by loss** ranking on Insights → Party rankings. Sits between "by profit" and "by cash in". Filters parties with `net < 0`, sorted ascending (worst first). Default shows 5 with "View N more" toggle. Empty case shows "No data for this period."

### Fixed
- **Print 2-pages issue** — clicking Print on Daily Net Profit or Net Profit by Month was outputting two pages with an adjacent chart appearing. Root cause: no `max-height` on print SVGs; the cloned chart card's natural height could overflow one landscape page. Fix: `max-height: 14cm` on print SVGs, `page-break-inside: avoid` on overlay + cloned card.
- **Scroll glitch (defensive fix #1)** — `_preserveScrollAround` was clamping captured scrollY to the new (sometimes shorter) document max, causing a visible upward jump. Changed: only restore scroll if `scrollY <= maxY + 5`, otherwise reset to 0. This addresses one possible cause; the actual root cause is fixed in v89.31.2.

### Hash
`5e48487f47f0127fe98fe65566285ccc`

---

## [v89.31.0] — 2026-05-20

**Parties feature: contact metadata + birthday awareness.**

### Added
- **Party contact metadata**:
  - Date of birth (full date or month-day with optional year)
  - Multiple phone numbers (up to 10) with country code as free text
  - Multiple email addresses (up to 10) with loose RFC validation
  - Free-form description (max 500 chars)
- **Edit permissions** — anyone in the business with role owner / manager / staff can edit contact metadata; viewers cannot. The party's *name* remains restricted to the original creator (`canRenameParty`).
- **Birthday banner on Entries page** — dismissible per-day (localStorage key `hisabs_bday_banner_dismissed_v1`). Shows party name, age when year is known, and chip per celebrating party. Supports multiple birthdays the same day.
- **Birthday badge on party detail** — "Birthday today · turned 36", "Birthday tomorrow", "Birthday in 25 days" depending on proximity. Filled accent for today, soft accent for ≤7 days, default for further out.
- **Contact card on party detail** — click-to-call (`tel:`), click-to-WhatsApp (`wa.me`), click-to-email (`mailto:`) buttons. DOB row, notes section.
- **Activity log integration** — `party_created`, `party_edited` (with `fields_changed` array: DOB / phone / email / description), `party_deleted` (with `entries_unlinked` count). Owners see all events; staff see their own.

### Database
- New SQL migration: `sql/v89.31.0_app_parties_meta.sql`
- Adds `meta jsonb` column to `app_parties` (idempotent, backward-compatible)
- CHECK constraint `app_parties_meta_is_object` rejects non-object payloads
- RLS unchanged — existing policies cover the new column

### Hash
`eb35e1da59a4fb3b2245d137190a1451`

---

## [v89.30.8] — 2026-05-20

### Changed
- **Chart sizing** — removed `max-width: 560px` cap on chart cards (cards were looking lonely on big screens). Chart SVG height now scales gently with viewport: `clamp(220px, 18vw, 360px)`. Mobile (≤880px) unchanged with `min-height: 180px`.
- **Device names** — User-Agent parser now produces richer "Brand · OS Version · Browser Version" strings. Detects Samsung (SM-*), OnePlus (CPH-*), Pixel, Xiaomi/Redmi, Realme, Vivo, Oppo, Huawei, Motorola, Nokia, Asus, LG, Sony, Poco. iPhone shows "iPhone · iOS 17.4 · Safari 17". Privacy note: browsers do not expose marketing names like "Galaxy S24 Ultra".

### Hash
`f89c75a30d6c3641fd5c2e220e108d1e`

---

## [v89.30.5] — 2026-05-19

### Added
- **App device names table** — `sql/v89.30.5_app_device_names.sql` adds `app_device_names` (user_id, session_id, name, created_at, updated_at). Lets users assign friendly names to their browser sessions ("MacBook · Home", "iPhone · Travel"). RLS restricts read/write to own rows.
- Edge functions deployed:
  - `delete-self-account` — final auth row removal after user-data deletion
  - `list-my-sessions` — joined session + device-name listing
  - `revoke-my-session` — atomic ownership-check-and-delete via SECURITY DEFINER RPC

---

## [v89.30] — 2026-05-18

### Changed
- **Invoice # column** removed from CSV / PDF exports (entry numbering was confusing in multi-business contexts).

### Fixed
- Distribution view: distSalaries / distShares now mirrored to in-memory `__distSalaries` / `__distShares` so the per-row final calculation reflects unsaved input.
- Distribution view: bottom full-width Save button now toggles in lockstep with the top one.

---

## [v89.29] — 2026-05-17

### Changed
- **Export progress feedback** — slow CSV / PDF exports now show a "Preparing…" splash so the user knows the click registered. Double-clicks are debounced to prevent multiple downloads.
- **LRU bounded** for the recent-self-writes set (was unbounded, would have grown over a long session).

---

## [v89.28] — 2026-05-16

### Added
- **OTP-triggering action splash** — instant feedback for "Send code", "Verify it's you", etc. Hides on success / error / throw so the user is never left looking at a spinner.
- **hideBootSplash** sequencing — modal renders before splash closes, no flash of bare auth screen.

---

## [v89.27] — 2026-05-15

### Changed
- **Render minimisation** — Distribution and Audit Tax views now use surgical text updates instead of full innerHTML rewrites where possible. Reduces input-focus loss during realtime sync events.
- **Visibility-based hiding** instead of display:none for certain layout-sensitive groups so the column structure doesn't reflow.
- **Restored lock pattern** for salaries + shares (regression from earlier refactor).

---

## Earlier versions

For changes prior to v89.27, see commit history in the repo.

---

## How to inspect what version is live

1. Open hisabs.app in DevTools → Console
2. Run `hisabsSelfTest()` — output prefix tells you the build is functional
3. The version embedded in code comments is the latest tag in this changelog

To verify the bundle hash matches what was deployed:
```
md5sum index.html
```
Compare to the hash in this changelog.
