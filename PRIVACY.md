# Privacy Policy

**Effective:** May 13, 2026
**Last updated:** May 13, 2026

This is the privacy policy for **Hisabs**, a cloud-synced bookkeeping web app. It explains plainly what happens to your data.

---

## The short version

Hisabs is a personal bookkeeping app. Your data lives in two places: your **browser** (for fast access while you work) and the **Supabase** database (for safe storage and cross-device sync). You can access it from any device by signing in. Nobody else can read it — not us, not the hosting providers, not other Hisabs users.

We don't show ads, sell data, run analytics, or track you in any way.

---

## What we store, and where

### In the cloud (Supabase)

When you use Hisabs, the following is stored in your Supabase project:

- Your sign-in email (for authentication)
- Your password — stored only as a one-way cryptographic hash, never readable as plain text
- Your display name and a user-profile row
- Every business you own — name, currency, settings
- Every book, entry, party, category, account, account group, audit expense in those businesses
- Staff invitations you've sent or received, with display names for the inviter and business
- Server-side timestamps (created, updated)

This data is uploaded as you work. The sync indicator at the top of the screen shows the current state.

### In your browser only

- Appearance preferences (theme, accent color, period filter)
- Auto-backup snapshots (last 3, taken every 30 minutes, kept locally for recovery)
- UI state (current view, scroll position, draft entry text)
- A random device identifier used to deduplicate sync events (not linked to your identity)
- A cached copy of your data for fast access while offline

---

## Who can see your data

Row-level security on the database means **only you can read your business data**. The owner of a business has full access; staff members you've invited can see businesses they've accepted into; nobody else can read any of it.

The Supabase project administrator (the person who set up the backend — that's likely you if you self-deployed) holds the keys to the database and could technically inspect it. If Hisabs is being run for you by someone else, you're trusting that operator.

The hosting provider (Vercel for the app, Supabase for the database) can see network metadata — your IP address, request timestamps — like any web service. They cannot see your business data unless they have the database credentials.

---

## What we don't do

- No advertising
- No analytics or telemetry — we don't track your usage
- No selling, sharing, or transferring of your data
- No third-party tracking pixels, cookies, or fingerprinting
- No cross-site tracking — Hisabs runs only on its own domain
- No third-party scripts run in the app (Supabase's JS library is the only external dependency, and it talks only to your Supabase project)

---

## Storage details

Hisabs uses your browser's `localStorage` to keep you signed in and cache data. Storage keys are prefixed:

- `sb-*` — Supabase's session/auth library (your sign-in token)
- `ledger_*` and `hisabs_*` — Hisabs's own data and preferences

These are functional storage, not tracking cookies. Clearing site data will sign you out and remove your local cache; your cloud data is unaffected and will reappear when you sign in again.

---

## Cross-device sync

When you make a change on one device, it uploads to the cloud within a few seconds, and any other device signed into the same account receives the change shortly after via a realtime channel. This works while online; while offline, changes queue locally and sync once you reconnect.

The sync engine uses Supabase Realtime, which transmits row-level changes over an authenticated WebSocket. The connection is encrypted (wss://) end-to-end.

---

## Deletion

When you delete a record — business, account, entry, anything — it is **permanently removed** from the cloud database within seconds. There is no soft-delete or trash bin. Deletion cascades: deleting a business removes all its books, entries, and associated data in one transaction.

To delete **everything**: **Settings → Data → Danger zone → Delete all my data and sign out**. This removes every business you own, your profile row, and signs you out everywhere. Your authentication account (email + hashed password) remains registered with Supabase — to remove that too, contact support.

Once data is deleted, it cannot be recovered from the cloud. If you may want to undo, download an auto-backup from **Settings → Data → Auto-backups** before deleting.

---

## Backups you control

You can download your data anytime:

- **Settings → Data → Backup everything** — JSON file of all your businesses
- **Sidebar gear next to a business → Backup & restore** — one business at a time
- Auto-backups are stored locally (browser only) — never uploaded — and you can download them from Settings → Data

Backup files contain your business data but not your password.

---

## Staff invitations

When you invite someone, their email goes onto an invitation row in `app_members`, visible to the business owner and to the invitee (matched on their authenticated email). The invitee sees the invite when they sign in. Currently invitations do not generate automatic email notifications — invitees discover them by signing in themselves.

The invitation card displays the inviter's name and the business name. These are stored on the invitation row so the invitee sees something meaningful before accepting.

---

## Hosting

- App code is served from Vercel as static files (HTML, JS, CSS)
- Database, auth, and realtime are provided by Supabase
- Vercel sees standard request metadata (IP, timestamp, user agent) — cannot see your data
- Supabase hosts the database in a region chosen at project setup time

If you forked Hisabs and host your own copy, this section applies to your providers.

---

## Children

Hisabs is bookkeeping software intended for adults running businesses. We don't knowingly collect data from anyone under 13. If you believe a minor has signed up, contact support so the account can be removed.

---

## Changes to this policy

If Hisabs's data handling changes meaningfully, this policy will be updated. The "Last updated" date at the top reflects the most recent revision. Significant changes will be noted in release notes.

---

## Contact

Hisabs is a personal-use bookkeeping tool. The owner of your deployment is the only contact. If you self-host, that's you.

If you're hosting Hisabs for other people, replace this section with your own contact information.

---

## In one sentence

Your data is yours, encrypted in transit, locked down by row-level security, and deleted permanently when you say so.
