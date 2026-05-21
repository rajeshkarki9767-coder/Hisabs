# Hisabs Changelog

All notable changes to Hisabs are documented here. Format roughly follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) but pragmatically — this is a single-developer project and the changelog is for orientation, not formal release management.

## Versioning

- **Major** (`v89.x`): the current generation. Single-file PWA built around Supabase + Vercel.
- **Minor** (`v89.31`): feature additions.
- **Patch** (`v89.31.x`): bug fixes and refinements within a feature.

The version is embedded in code comments throughout `index.html` (`// v89.31.2: ...`) for traceability. Deployed builds are identified by the md5 hash of `index.html`.

---

## [v89.31.6] — 2026-05-21

A focused refinement batch responding to user feedback across Settings, Team & Access, New Entry, Parties, Insights, Distribution, exports, and search.

### Hash
`fede32240f3d7d67f5a93b234291c444`

### Added
- **Crop & confirm before saving a profile photo** — picking a photo in Settings → Your account now opens a crop dialog (drag to reposition, zoom slider) so you choose exactly what gets saved, instead of an automatic centre-crop.
- **Entry-count badge in detail views** — opening a party, category, or account shows the number of entries (for the active period) right next to its name in the header.
- **SMS / Email contact badges on Parties** — a saved phone shows a small "SMS" badge and a saved email shows an "Email" badge after the party name (blue outline), replacing the previous single green dot. Both appear when both are saved.

### Changed
- **Double confirmation for role changes** — changing a team member's role on Team & Access now asks twice before applying (removal already required two steps).
- **Country code now drives party phone fields everywhere** — the example placeholder and hint in both New Party and Edit Party reflect the business's configured country code (e.g. `+1` for a US business) instead of always showing `+977`. Newly-added phone rows follow suit.
- **Recently-added party sorts to the top reliably** — creating a party now jumps the list to "Recently added" and the new party appears first, even when several parties are created on the same day (previously same-day parties could tie and not surface).
- **Entry count removed from the list cards** — the count chip no longer sits on the Parties / Categories / Accounts cards; it lives in the detail header instead (see Added).
- **Insights "worst day" excludes today** — because today's figures are still incomplete, the worst-day card now considers only fully-elapsed days. The best-day card can still be today.
- **Removed the "View only" banner on Distribution** for managers and viewers. The page remains read-only for non-owners (inputs stay disabled) — only the notice was removed.

### Fixed
- **Arrow-key Cash In / Cash Out shortcut now works on the New Entry card.** Left arrow selects Cash In, right arrow selects Cash Out, even while the amount field has focus (previously the shortcut was suppressed whenever an input was focused, which is almost always during entry).
- **Invoice number now prints.** The on-screen invoice-number badge was hidden by a stale print rule from when the Invoice # column had been removed from PDF/CSV; that column was re-added in v89.31.4, so the badge now appears in printed pages and screenshots too.
- **No more browser "recent search" suggestions.** All seven search fields (universal search desktop + mobile, entries, parties, categories, accounts, quick-look) now fully suppress native autocomplete/history.

### Notes
- No new SQL migration is required for this batch. The party `createdTs` value is derived locally (and reconstructed from the stored date for cloud-pulled records), so no schema change was needed.
- Existing v89.31.4 + v89.31.5 migrations are still required for a first deploy (all idempotent).



A small follow-up batch: team-management refinements, a polished post-sign-in splash, and profile pictures.

### Added
- **Edit a team member's role inline** — on the Team & access page, each member who has joined now has a role dropdown (Manager / Team / Viewer). Changing it prompts for confirmation and propagates to that person on their next sync. (Ownership transfer remains a separate flow.)
- **Per-member "sees totals" control** — whether a Team member can see totals (Cash In / Cash Out / Net and balances) on the Entries view is now set **per person** on the Team & access page, and is **off by default**. Managers and viewers always see totals. This replaces the old single business-wide toggle.
- **Profile picture** — Settings → Profile now has a profile-picture uploader. The chosen image is center-cropped, downscaled (≤256px) and compressed client-side to a small JPEG, shown as your circular sidebar avatar, and synced so it follows you across devices. A Remove option clears it.
- **Polished full-page splash after sign-in / account creation** — the branded splash now reliably holds for ~2 seconds measured from the moment you tap Sign in (or finish entering your account-creation code), not just from page load. The splash got a visual upgrade: a layered accent-gradient wash, a faint ledger-ruling texture, and a thin indeterminate progress bar — clearly covering the whole page. Honors reduced-motion.

### Changed
- **Business Settings** no longer has the "Team can see totals on entries view" toggle — that control moved to Team & access (per member). A short note in business settings points there.
- **Documentation** — the User Guide now covers inline role editing, the per-member totals control, and the profile-picture uploader. The Privacy Policy notes that an optional profile picture is stored (compressed) in your cloud profile row.

### Migration required
Run BOTH in the Supabase SQL editor **before** deploying this build (the sync maps now reference these columns; without them, member/profile pushes would fail). Both are idempotent (`ADD COLUMN IF NOT EXISTS`).
- **`sql/v89.31.5_app_members_sees_totals.sql`** — adds `member_sees_totals boolean NOT NULL DEFAULT false` to `app_members`.
- **`sql/v89.31.5_app_accounts_avatar.sql`** — adds `avatar_url text` to `app_accounts`.

### Notes
- The old business-wide `app_businesses.staff_sees_totals` column is now unused but left in place (harmless) so older clients don't error. It can be dropped in a later cleanup.
- Profile pictures are stored as base64 data URLs in the profile row (a few KB to ~30KB after compression; the client refuses anything over ~500KB). If avatar sizes ever grow, the field can migrate to Supabase Storage with no app change (it's treated as an opaque string).

### Hash
`65a7405259fb3ca58442655d2e04488d`

---

## [v89.31.4] — 2026-05-21

A 13-item batch of user-requested fixes and refinements gathered after living with v89.31.x for a few days. Spans parties, exports, printing, sounds, distribution access, and documentation.

### Added
- **Party contact details & green dot** — each party can store optional phone numbers, emails, date of birth, and notes. A small green dot appears next to a party's name on the Parties list when it has at least one saved phone or email.
- **Country-code suggestion in New Party** — the phone field in the New Party form is pre-filled with a suggested dialing code (e.g. `+977`). The suggestion follows the business currency by default, and the owner can pin a specific code in **Business settings → Business identity → Default country code**. A code-only entry (no actual number) is never saved.
- **Invoice number in exports** — both the PDF and CSV (Excel) exports now include each entry's invoice number (`#1`, `#2`…), matching exactly what's shown on the entries list. Reverses the v89.30 removal.
- **Full-page colour print** — the print / Save-as-PDF action now produces a faithful, full-page colour copy of the current view: app chrome (sidebar, topbar, FAB) is hidden, on-screen colours/backgrounds are preserved (`print-color-adjust: exact`), and long entry lists are expanded to print every row. Implemented as dependency-free print CSS (no html2canvas, keeping the bundle lean and offline-first).
- **Distribution for managers & viewers (read-only)** — the Distribution view is now visible to managers and viewers, not just the owner. They see exactly how the owner has configured salaries, profit shares, and the split, with all inputs disabled and a "View only" banner. Owner retains full edit; staff still don't see it.
- **Entry-count chip per filter** — each filtered entries view shows a count chip for the active filter.
- **"Recently added" sort for parties.**
- **Self-test coverage** — `window.hisabsSelfTest()` extended to 45 checks, adding cases for `isMeaningfulPhone()` and `bizPhoneCodeSuggestion()`.

### Changed
- **Action sounds are now consistent** — cash-in, cash-out, and delete each play the same dedicated sound every time. Root causes fixed: (1) the MP3→Web-Audio-synthesis fallback produced a *different* sound when the embedded clip didn't resolve in time — the synth fallback is removed, so a given action always plays one deterministic sound; (2) each action now uses one preloaded, reusable `Audio` element rewound per play, eliminating per-play construction races on mobile; (3) the delete sound previously read the *Announcement* mute key while cash sounds read the *Entry* key — all three action sounds now follow the single **Entry** toggle in **Settings → Notifications**.
- **Amount field input hardening** — pressing `ArrowLeft` sets the entry type to Cash In and `ArrowRight` to Cash Out (matching the on-screen button order); the letter `e` (and `+`/`-`) can no longer be typed or pasted into the amount field.
- **Pagination** — the entries list shows the first 200 rows with a "Show next 200" control; verified the clamp and increment behaviour.
- **Documentation** — the User Guide gained sections on party contact details + green dot, the country-code suggestion, action sounds, full-page printing, invoice numbers in exports, and read-only Distribution for managers/viewers. The Privacy Policy now discloses that optional party contact metadata (phone, email, DOB, notes) and per-business preferences (currency, default phone country code) are stored in the cloud.

### Fixed
- **Drag-to-select no longer closes the card** — selecting text by dragging inside an entry/modal input could close the modal when the drag ended over the backdrop (a `click` fired on the backdrop). The backdrop now only dismisses when the press *began* on the backdrop itself (pointerdown-origin guard), so text selection that starts inside the modal never closes it.

### Migration required
- **`sql/v89.31.4_app_businesses_phone_code.sql`** — adds the `phone_country_code` column to `app_businesses`. **Run this in the Supabase SQL editor BEFORE deploying this build**, since the businesses sync map now references the column; without it, pushes that include a business row would fail. The migration is idempotent (`ADD COLUMN IF NOT EXISTS`).

### Notes
- The full-page print is a faithful print-CSS rendering, not a raster screenshot; html2canvas was deliberately not bundled (~200KB) to preserve the single-file, offline-first design.

### Hash
`3f79e0f9300bc3f5cd8ec2bfd41de1e6`

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
