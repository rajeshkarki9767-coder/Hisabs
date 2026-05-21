# Hisabs Changelog

All notable changes to Hisabs are documented here. Format roughly follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) but pragmatically — this is a single-developer project and the changelog is for orientation, not formal release management.

## Versioning

- **Major** (`v89.x`): the current generation. Single-file PWA built around Supabase + Vercel.
- **Minor** (`v89.31`): feature additions.
- **Patch** (`v89.31.x`): bug fixes and refinements within a feature.

The version is embedded in code comments throughout `index.html` (`// v89.31.2: ...`) for traceability. Deployed builds are identified by the md5 hash of `index.html`.

---

## [v89.32.11] — 2026-05-21

Hardened the time-zone picker against cross-browser zone-name differences.

### Hash
`c1e3b4131d15a5e437d46addc5e82ab3`

### Changes
While verifying the v89.32.10 picker, found a real cross-browser edge case: different JS engines can use slightly different canonical names for the same zone (e.g. `Asia/Kathmandu` vs the older `Asia/Katmandu`), and ICU data varies by version. If a business's stored time zone wasn't in the current engine's list, the picker showed nothing selected and could silently reset the zone on the next save from a different device.

Fixes:
1. **The currently-stored zone is now always included as a selectable, pre-selected option** in the picker, even if it isn't in the standard list — so the saved zone is never visually lost.
2. **Save guards now validate by formattability** (`isValidTimeZone` — can the engine actually format with it?) instead of strict list membership, so a legitimately-selected zone is never rejected, while garbage values are still refused.

Self-test 63/63; picker + validator trace 8/8.

---

Removed the per-book sidebar gear; richer time-zone picker labels.

### Hash
`6497c065627350eb02afe28a018aa71e`

### Changes
1. **Removed the per-book gear icon** from the sidebar book list. Book names are now edited only from **Business Settings → Books** (Rename / Delete there), keeping book editing in one place. Removed the now-orphaned `renameBookFlow` and its dead CSS (`.book-gear`, `.book-item-right`).
2. **Time-zone picker now shows UTC/GMT offset + city** for every zone, e.g. `(UTC+05:45) Kathmandu — Asia`, `(UTC-04:00) New York — America`. Options are sorted west→east by current offset (DST-aware), making it much easier to find and set the right zone. Applies to both the new-business modal and Business Settings.

Self-test 63/63.

---

Simplified the dashboard clock to zone + time only.

### Hash
`6e2db4c6d2d668ed93dcd942eb80a2e4`

### Changes
- The dashboard clock now shows only the **time zone and time, side by side** in the middle. Removed the date from the clock, since the date strip directly below it already shows the date. Cleaned up the now-unused date-update loop in the per-second ticker.

Self-test 63/63.

---

Full date rewire: all business-day logic now follows the business time zone.

### Hash
`628abaaabacb4f4304c6c6e671d05b19`

### Audit cleanup (final deep audit pass)
- Fixed a subtle chart edge case: the cumulative-line "today" marker mixed the device month with the business month, which could desync near a month boundary across zones. Now derives both from the business calendar day.
- Removed dead code orphaned by the always-on birthday banner (the per-day dismiss helpers and their localStorage key).

### Changes
Building on the per-business time zone (v89.32.7), the app's core date helpers are now business-zone-aware, so "today" across the whole app is the active business's calendar day rather than the device's:

1. **`today()` / `yesterday()` / `todayYmd()`** now resolve to the active business's time zone (falling back to the device zone when no business is active or no zone is set). Because nearly all business-day logic flows through these helpers, this single change carries the business zone into: the **default entry date**, **period filters** (This Month / Today / Yesterday / Custom), **entry-number monthly buckets**, **birthday detection**, the **relative-date hint** in the entry modal, and the dashboard clock.
2. **`deviceToday()` / `deviceYesterday()`** preserve the original device-local behaviour for anything that is genuinely about this device's wall clock.
3. Implemented via a single chokepoint (the date helpers) rather than rewriting 80+ individual call sites, which keeps the change auditable and avoids missing or mis-converting sites. When the business zone equals the device zone (the common case), behaviour is identical to before.

### Verification & honest caveat
Self-test 63/63 (it exercises entry numbering and period logic, all of which call `today()`), plus a dedicated trace with extreme zones (Kiritimati UTC+14, Pago Pago UTC-11) confirming `today()`/`yesterday()` track the active business and fall back safely. Cross-time-zone behaviour (a device in one zone, business set to another, entries/filters/birthdays flipping at the business midnight) should be confirmed on real devices — that's the scenario static checks can't fully exercise.

Requires the v89.32.7 `time_zone` column migration (no new SQL this release).

---

Replaced the per-device dual clock with a per-business time zone.

### Hash
`4702c1b39d0ee20160e5f07b23b714cd`

### Changes
1. **Removed the dual clock / per-device clock settings** added in v89.32.6 (wrong model).
2. **Per-business time zone.** Each business now has its own IANA time zone, set by the owner when **creating** the business and editable in **Business Settings → Time zone** (owner only). It syncs across devices on the business row.
3. **One clock on the dashboard** at the top of the main entries page shows the **active business's** time zone, labelled (e.g. "Kathmandu"), with time + date, ticking every second.
4. **"Today" follows the business zone** for the two highest-impact, lowest-risk consumers: **birthday detection** (a birthday flips at midnight in the business's zone) and the **default entry date** (new entries default to the business's calendar day). Older businesses with no zone set fall back to the device zone.
5. **SQL:** added `sql/v89.32.7_app_businesses_time_zone.sql` — adds a nullable `time_zone` column to `app_businesses`. Backward compatible (NULL = device fallback). **Run once in Supabase.**

### Scope note
Date/time logic elsewhere (period filters, totals bucketing, daily digest, etc.) still uses the device's local day for now. Rewiring every date consumer to the business zone is deeper, higher-risk work and was intentionally not bundled here; the `businessTodayYmd()`/`businessTimeZone()` helpers added in this release make that migration possible to do incrementally and safely.

Self-test suite remains 63/63.

---

Birthday banner is always-on; new dual clock on the dashboard.

### Hash
`64633e86c8ae27f45728b919deb85ee0`

### Changes
1. **Birthday banner always shows.** Removed the Settings toggle added in v89.32.5 and the per-day dismiss ×. If any party has a birthday today, the banner always appears on the entries page and cannot be hidden.
2. **Dual clock on the main entries page.** Added a **Clocks** section in Profile Settings with two time-zone pickers — a **Main clock** (defaults to this device's time zone) and an optional **Second clock**. Both render at the top of the main entries page, each labelled with its time zone (e.g. "Kathmandu" / "New York"), showing time + date and ticking every second. Time-zone choices are stored per-device (a clock reflects where the user is, so it isn't synced or per-business). Uses the browser's built-in IANA time-zone data — no external library, works offline. Invalid/unsupported zones fall back to local time without error.

Self-test suite remains 63/63.

---

Birthday-notice control, app-wide keyboard-glitch fix, and realtime sync enablement.

### Hash
`6883b26aeeef07c68d9bdd7786c9f634`

### Changes
1. **Birthday reminders can now be turned off for good.** The × on the birthday banner only ever hid it for the current day, so a recurring birthday looked like it "couldn't be hidden." Added a **Birthday reminders** toggle in Settings → Notifications; when off, the banner never renders. The per-day × dismiss still works as before when the toggle is on.
2. **Fixed the mobile keyboard glitch across all input fields.** Focus preservation across background re-renders (realtime/sync events) was limited to a hand-picked allow-list, so other fields — party/category/account search, the party edit fields, and more — lost focus mid-type and the keyboard closed/reopened ("pushed back"). Focus is now preserved for **any** focused input/select/textarea with an id (password and file inputs excepted), keeping the keyboard up and the caret in place during background updates.
3. **Realtime sync without refresh (SQL).** Added `sql/v89.32.5_enable_realtime.sql`. The client already subscribes to live changes for every synced table, but Supabase only broadcasts changes for tables in the `supabase_realtime` publication. If announcements/entries only appeared on a teammate's device after a manual refresh, those tables weren't in the publication. The migration adds all 14 synced tables to the publication and sets `REPLICA IDENTITY FULL` so update/delete payloads carry full rows. **Run this once in the Supabase SQL editor.** (No client code change was needed — subscription, apply, re-render, and focus/reconnect catch-up were already correct.)

Self-test suite remains 63/63.

---

Team & Access invite-flow fixes.

### Hash
`434e4e886229a06bae9b705d15ffe439`

### Changes
1. **Fixed: invite email box lost focus while typing.** The Team & Access "Phone or email" field (`pgStaffLogin`) wasn't in the focus-preservation allow-list, so a background realtime/sync event (e.g. a teammate's entry arriving) tore down the input mid-type — dropping focus and dismissing the mobile keyboard, which felt like the field "pushing you back." Added it to the preserved-inputs list.
2. **Fixed: accepted invite reappeared until app restart.** When a user accepted an invite, the post-accept cloud pull could race ahead of the not-yet-drained accept op and re-fetch the membership row as still `pending`, reverting the local `accepted` status — so the invite kept reappearing and the business only showed after reopening the app. Two-part fix: (a) the pull merge now refuses to downgrade a locally-accepted membership for the current user back to pending, and (b) `respondInvite` re-asserts acceptance after the pull and re-queues the update so the cloud converges automatically. The business now appears immediately and the invite stays accepted.
3. **Hardening:** member display-name avatar initial now has a `"?"` fallback, removing a latent crash risk if a membership row ever had an empty name/login.

Self-test suite remains 63/63; added a 7-case invite-guard trace.

---

Small UX addition.

### Hash
`3925d16b4314921b1026e8e18ff508a9`

### Changes
1. **Copy social handles from a party.** When you open a party, each saved social handle in the contact card now has a one-tap **Copy** button (next to the existing **Open** link for URL handles). Uses the Clipboard API with a textarea fallback, briefly showing "Copied" on success.

---

UI reorganization.

### Hash
`097a4e6048f396046ac865952c730a29`

### Changes
1. **Moved individual export/import to the Advanced tab.** The per-business "Export categories/parties/accounts" and "Import categories/parties/accounts" controls were moved out of the Business tab and consolidated under the existing **Advanced → Backup &amp; restore (this business)** section, alongside the whole-business backup/restore. Note: the Advanced tab is owner-only, so these individual export/import controls are now owner-only as well (previously also available to managers) — consistent with the whole-business backup/restore that already lived there.

---

Bug fixes and refinements to the v89.32.0 feature batch.

### Hash
`d4732e50b24ec1384ab9f90eaafcb412`

### Changes
1. **Fixed: editing a party didn't save socials (and could appear to drop phone/email).** The party meta diff omitted the new `socials` field, so adding or editing a social handle on an existing party was detected as "no change" and the save silently bailed. Socials are now compared in the diff; adding/editing/removing a phone, email, or social on an existing party saves correctly and displays immediately.
2. **Detail pages: "Rename" → "Edit".** On an individual party, category, or account page, the top-right button now reads **Edit** and opens the full edit form (party: name, DOB, phones, emails, socials, notes; category: name, shortcut, unassigned; account: name, unassigned) instead of the rename-only prompt.
3. **Business Settings: individual export added.** The "Backup & import (this business)" section now has **Export categories / Export parties / Export accounts** buttons alongside the existing individual imports. Exports use the same file shape the importer accepts, so a list exported from one business can be imported into another.

Self-test suite remains 63/63.

---

A feature batch: detail-view period filters, social handles for parties, merge-import, and several UX fixes.

### Hash
`2cdc5f7029324d9712bd07e02bbe40d6`

### Changes
1. **Period filter on individual detail views.** The This Month / Today / Yesterday / All Time / Custom filter (default This Month) now appears at the top of each individual party, category, and account detail page, filtering that item's entries and totals. Distribution also shows the filter at the top.
2. **Forecast** confirmed already locked to the current month with no filter bar (no change needed).
3. **Splash & sign-in.** Boot splash minimum raised to 3 seconds everywhere. Fixed the brief "no business" dashboard flash after sign-in by painting the business view before fading the splash.
4. **Device names.** The Devices list now resolves the exact device model via the User-Agent Client Hints high-entropy API where the platform allows (e.g. "Pixel 8 · Android 14"), shows the current device instantly while the server list loads, and supports renaming. Note: browsers do not expose the OS-level device name (e.g. "Rajesh's iPhone") to web apps; rename for a precise label.
5. **Merge import.** New non-destructive import in Profile Settings (categories, parties & accounts into the active business) and Business Settings (individual import for categories, parties, accounts). Matching names are updated in place (preserving ids so entries stay linked); new names are added; nothing is deleted; transactions are not imported. A preview confirms counts before applying.
6. **Sidebar order.** Businesses now appear above Books.
7. **Social handles for parties.** New "Social" section in the party create/edit form — side-by-side platform + handle/link rows with "add another" (up to 12) and a datalist of common platforms (free-text). Saved socials show as blue badges on the party card (like SMS/Email) with a "+N more" badge when there are many, and appear in the party's contact card with clickable links for URL handles. Stored in party meta, so they sync automatically.

Self-test suite now 63/63.

---

Three user-requested refinements to Parties, Team & Access, and Business Settings, plus a dead-code cleanup.

### Hash
`476177bb255db3182b9a35f0be943ad0`

### Changes
1. **Parties — contact badges below the name.** The "SMS" / "Email" badges on a party card now sit on their own row directly below the party name (previously inline to its right) and use a fixed blue (`#2563eb`) regardless of the active theme accent.
2. **Business Settings — removed the totals description.** The note explaining that totals visibility is set per team member has been removed from Business Settings. The per-member **"Sees totals on entries"** toggle remains on the **Team & Access** page (staff can still be individually granted totals on the Entries view); owners, managers, and viewers always see totals.
3. **Business Settings — "Set Dial code" free-text field.** Replaced the country-code dropdown (which collided US/Canada on the shared `+1` value, flipping US→Canada on save/reload) with a free-text input. Users can enter any dial code; it's normalized to a clean `+<digits>` form and round-trips exactly. No example codes are shown in the field's placeholder or help text. Blank falls back to a currency-derived code. The entered code prefills the phone field when creating or editing a party (existing party phones are never overwritten). 8 `normalizeDialCode` self-tests (suite 53/53).
4. **Cleanup.** Removed three now-orphaned items left over from the above changes: the `phoneCodeOptionsHTML` function (old dropdown builder, 0 callers), the `partyHasContact` function (superseded by `partyContactBadges`), and the `.party-contact-dot` CSS rule (the old green-dot indicator). No behavior change; ~2.2 KB smaller.

---

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
