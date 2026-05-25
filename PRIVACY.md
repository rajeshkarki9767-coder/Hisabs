# Privacy Policy

**Effective date:** May 16, 2026
**Last updated:** May 16, 2026

This Privacy Policy explains how **Hisabs** ("the App", "we", "us") collects, stores, uses, and protects information when you use the App. It is written in plain language; please read it carefully. By creating an account or using the App, you agree to the practices described below.

If you self-host Hisabs, replace the **Contact** section at the bottom with your own details — you become the data controller for your deployment.

---

## 1. Summary

- Hisabs is a personal and small-business bookkeeping app. Your data is yours.
- We store your business records in a Supabase database protected by row-level security, and cache a copy locally in your browser for offline use.
- We do **not** run ads, analytics, or telemetry. We do **not** sell, share, or transfer your data to third parties.
- You can export your data at any time and permanently delete your account from inside the App.

---

## 2. Data we collect

We collect only what is needed to run the App. We never collect data passively, and we never collect data you have not personally entered.

### 2.1 Account data

When you create an account, we store:

- **Email address** — used as your sign-in identifier and for password recovery.
- **Password** — never stored in plain text. It is hashed and salted by Supabase Auth before being written to the database. We cannot read or recover your password; we can only reset it.
- **Display name** — the name you choose, shown in the app and on records you create.
- **Account creation timestamp** and **last sign-in timestamp**.
- **Authentication session tokens**, stored by the Supabase Auth client in your browser's `localStorage` under the prefix `sb-*`.

### 2.2 Business data

For each business you create, we store:

- The business name, currency, tax rate, and owner-defined settings.
- Books (ledgers) within the business.
- Entries (transactions): date, amount, type (cash in / cash out), party, category, account, optional note, and timestamps.
- Parties (customers, suppliers, contacts).
- Categories (Sales, Rent, etc.).
- Cash accounts and account groups (Cash, Bank, Wallet, Card, etc.).
- Internal transfers between your accounts.
- Audit expenses (rent, utilities, etc.) used to compute operating and net profit.

### 2.3 Team and collaboration data

If you invite staff to a business, we store:

- The invitee's email address (for matching to a Supabase account).
- The role assigned (Manager, Team, or Viewer).
- The invitation status (pending, accepted, declined) and timestamps.
- The inviter's name and the business name, so the invitee sees something meaningful before accepting.

### 2.4 Activity log

When you edit or delete an entry, we write an audit row containing:

- Who made the change (your user ID).
- When the change occurred (server timestamp).
- The entry's full content **before** and **after** the change.
- The business the entry belongs to.

Activity rows are **visible only to the business owner** through row-level security. The most recent 500 rows per business are retained; older rows are automatically pruned.

### 2.5 Announcements and read receipts

If a business owner posts an announcement, we store:

- The announcement body, author name, importance flag, and timestamps.
- When you view or react to an announcement, a row is written linking your user ID to the announcement.
- The business owner can see who has seen the announcement and who has reacted; you can see only your own receipts.

### 2.6 Push notification subscriptions (optional)

If you enable browser push notifications, we store:

- Your browser's push endpoint URL and public encryption keys, supplied by the Web Push API.
- The user-agent string of the device that subscribed (to label sessions).

The subscription is removed when you sign out, disable notifications, or revoke the device. Push messages are sent only when a business owner posts an announcement; we never send promotional or marketing pushes.

### 2.7 Cloud backups (optional)

If you create a "cloud backup" of your data, we store a single most-recent snapshot of your business data as a JSON blob under your user ID. This is overwritten each time you create a new cloud backup.

### 2.8 Device and session metadata

To support multi-device sign-in, we store:

- A friendly device name (e.g. "Chrome on macOS") and a hashed session identifier.
- The last-seen timestamp, used to show you which devices are signed in to your account.

You can view and revoke individual device sessions from **Settings → Profile → Active sessions**.

### 2.9 Failed sign-in attempts

To slow down brute-force attacks, we record failed sign-in attempts (email + timestamp) and apply a short cooldown after repeated failures. These rows are cleared on a successful sign-in for that email.

### 2.10 Data stored only on your device

The following stays in your browser and is **never uploaded**:

| Key | Purpose |
| --- | --- |
| `ledger_data_v4` | Cached copy of your data for offline access |
| `ledger_accounts_v4` | Cached account list |
| `ledger_session_v4` | Active session pointer (which business, which view) |
| `hisabs_auto_backups_v1` | Last 2 auto-backup snapshots, taken every 30 minutes |
| `hisabs_per_biz_backup_v1` | Per-business manual backups you've saved locally |
| `hisabs_chime_muted` | Whether the teammate-entry chime is muted on this device |
| `hisabs_onboarding_dismissed` | Whether you've dismissed the onboarding card |
| `hisabs_install_dismissed_at` | Whether you've dismissed the "install as app" prompt |
| `hisabs_last_manual_backup` | Reminder timestamp for the manual-backup nudge |
| `hisabs_debug` | Verbose-logging toggle (off by default) |
| Theme / accent color preference | Your appearance settings |
| Device identifier | A random per-browser ID used to filter out your own realtime echoes (not linked to your identity) |

These values are functional storage, not tracking cookies. Clearing site data will sign you out and remove the local cache; your cloud data is unaffected and will reappear when you sign in again.

---

## 3. How data is stored and protected

### 3.1 Where data lives

- **Cloud (Supabase)**: a managed Postgres database, with authentication, realtime, and edge functions provided by Supabase. Data is stored at the region you (or your administrator) chose when the Supabase project was created.
- **Your browser**: a local cache (see section 2.10) for fast access and offline use.

### 3.2 Encryption

- Data in transit is protected by TLS (HTTPS) between your browser and Supabase, and by WSS (secure WebSockets) for the realtime sync channel.
- Data at rest in Supabase is stored on encrypted disk volumes managed by Supabase's infrastructure provider.

### 3.3 Row-level security

Every business-data table in our database has row-level security enabled. The policies enforce, server-side:

- **Business records** are visible only to the owner and to staff who have accepted an invitation to that business.
- **Activity log** rows are visible only to the owner of the business.
- **Announcement read receipts** are visible to the announcement's business owner and to the user the row belongs to.
- **User-private rows** (device names, push subscriptions, failed sign-in attempts) are visible only to the user they belong to.

These rules apply to every database query, including ones made through the App. Even if a client tried to query data it shouldn't see, the database would refuse.

### 3.4 Authentication and account handling

- Authentication is handled by Supabase Auth.
- Passwords are hashed with bcrypt before storage. We never see or store the plain text.
- Password resets are handled by Supabase Auth via a one-time email link. The link is single-use and expires automatically.
- Sessions are issued as JSON Web Tokens (JWTs). The App stores them in `localStorage` and refreshes them automatically while you are signed in.
- You can sign out of a specific device from **Settings → Profile → Active sessions**, or sign out everywhere by signing out from your current session and resetting your password.

### 3.5 Edge functions

A small number of privileged operations run inside Supabase Edge Functions, with a service-role key that never leaves the server:

- `check-user-exists` — used by the team-invite flow to verify an invitee has signed up.
- `delete-self-account` — performs the cascading deletion of your user record and all owned businesses.
- `list-my-sessions` — lists the active sessions on your account.
- `revoke-my-session` — signs a specific device out.
- `save-push-subscription` — persists a Web Push endpoint.
- `send-announcement-push` — delivers a push notification when an owner posts an important announcement.

Each function verifies your authentication token before running, and accepts requests only from the App's deployed origin (CORS allow-list).

---

## 4. Analytics and third parties

We use **no** analytics or telemetry services. There is no Google Analytics, Mixpanel, Segment, Plausible, Sentry, or similar. We do not embed third-party scripts, pixels, fingerprinters, or advertising SDKs.

The only third-party JavaScript loaded by the App is the **Supabase JavaScript SDK**, served from the App's own server. It communicates exclusively with your own Supabase project.

We do not sell, rent, share, or transfer your data to advertisers, data brokers, or any other party.

---

## 5. Cookies, local storage, and session usage

The App does not set tracking cookies. Authentication tokens and the local data cache are stored in your browser's **`localStorage`** (see section 2.10 for the full key list). These are required for sign-in and offline functionality and cannot be disabled without losing core features.

Some browsers send a small set of strictly necessary cookies as part of the TLS handshake or by Supabase's infrastructure. None of these are used for tracking or marketing.

---

## 6. Your rights and choices

You can exercise the following rights at any time, directly from inside the App:

- **Access your data** — Settings → Data → **Backup everything** downloads every business you own as a JSON file.
- **Per-business export** — Sidebar gear next to a business → **Backup & restore** downloads a single business.
- **Correct your data** — edit any entry, party, category, or business setting directly in the App.
- **Delete a specific record** — every record (entry, party, category, account, business, transfer) has a delete action. Deletion is immediate and permanent in the cloud database.
- **Delete your entire account** — Settings → Data → **Danger zone → Delete all my data and sign out**. This cascades through every business you own, then removes your Supabase Auth user via a privileged edge function. Once complete, your data cannot be recovered.
- **Withdraw consent** — sign out from any device, revoke active sessions, or delete your account.

We do not require you to contact support to exercise any of these rights.

---

## 7. Data retention and deletion

- **Active data** is retained for as long as your account exists.
- **Activity log rows** are retained for the most recent 500 entries per business; older rows are pruned automatically.
- **Failed sign-in attempts** are cleared on a successful sign-in for that email.
- **Auto-backups** (local) keep the last 2 snapshots and rotate. They never leave your browser.
- **Deleted records** are permanently removed from the cloud database within seconds. There is no soft-delete or trash bin.
- **After account deletion**, the cascading delete removes all your owned businesses, members, entries, transfers, announcements, read receipts, activity log rows, device records, and push subscriptions. The Supabase Auth user row is then removed by the edge function.

Backups you have downloaded to your own device, and any forwarded data (e.g. PDF or Excel exports you have shared), are outside our control and not affected by deletion.

---

## 8. Security practices and limitations

### What we do

- **TLS-only transport.** The deployment serves an HSTS header that asks browsers to refuse HTTP fallbacks.
- **Strict Content Security Policy** — only first-party scripts, no inline event handlers from untrusted origins, no `eval`, no third-party origins beyond Supabase.
- **Anti-CSRF posture** — all data-mutating requests go through the Supabase SDK and require a valid JWT bound to your session; cross-site form posts cannot impersonate you.
- **Frame-ancestors lockdown** — the App refuses to be embedded in third-party frames.
- **Row-level security on every business-data table** (see section 3.3).
- **Edge functions enforce auth** before running, and accept only the App's own origin via a CORS allow-list.
- **Password rate limiting** — repeated failed sign-ins for the same email are throttled by a short cooldown.
- **No service-role keys** are ever sent to the browser. The client uses only the public anon key, which is RLS-restricted to whatever the signed-in user is allowed to see.

### What we cannot guarantee

- We cannot defend you against a compromised device. If someone else has access to a signed-in browser or knows your password, they can see your data.
- We cannot recover data after permanent deletion. Keep a local backup if you may want to undo.
- We cannot prevent your hosting providers (Vercel, Supabase) from being legally compelled to disclose metadata or, in extreme cases, infrastructure access. We choose providers with strong security practices, but we do not control them.
- We do not currently support two-factor authentication. We expect to add it; until then, use a strong, unique password and consider a password manager.

If you discover a security issue, please contact us privately at the address in section 11 before disclosing it publicly.

---

## 9. Children

Hisabs is intended for adults running businesses. We do not knowingly collect data from anyone under 13. If you believe a minor has created an account, please contact us and we will remove it.

---

## 10. Changes to this policy

We will update this policy if our data handling changes meaningfully. The "Last updated" date at the top reflects the most recent revision. Significant changes are also noted in the App's release notes.

Continued use of the App after a change indicates acceptance of the revised policy.

---

## 11. Contact

Hisabs is operated by an independent developer.

For privacy questions, data-access requests, account-deletion help, or to report a security issue, please use the in-app **Settings → Support → Contact** option, or write to the email address listed there.

If you are hosting Hisabs for other people, this section should be replaced with your own contact information; you are the data controller for your deployment.

---

## In one sentence

Your data is yours, encrypted in transit, locked down by row-level security, never sold, never tracked, and permanently deleted when you say so.
