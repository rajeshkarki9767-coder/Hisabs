# Privacy Policy

**Effective:** May 12, 2026
**Last updated:** May 12, 2026

This is the privacy policy for **Hisabs**, a local-first bookkeeping web app. It explains, plainly and honestly, what happens to your data.

---

## The short version

Hisabs has no server. Everything you create — businesses, books, entries, parties, categories, accounts, audit expenses, settings — is stored only in your own browser, in the area called `localStorage`. Nothing is uploaded anywhere. There is no account on a remote system. We don't collect data, we don't sell data, we don't track you, and we don't have analytics.

If you stop trusting this policy, the simplest way to verify it is true: open your browser's developer tools, go to the **Network** tab, and use Hisabs for a while. You will see no outgoing requests to anyone.

---

## What we store, and where

When you use Hisabs, the following information is created and stored **in your browser only**:

- Your account name and login (phone number or email)
- Your password, in plaintext
- Every business, book, entry, party, category, account, and account group you create
- Audit expenses you log
- Staff invites you've sent or received
- Your appearance preferences (theme, accent color)
- Auto-backup snapshots (up to 3, kept for the last 90 minutes of activity)

This data lives in your browser under storage keys prefixed with `ledger_` and `hisabs_`. It does not leave your device unless **you** export it.

---

## Why your password is in plaintext

Hisabs is a single-device personal tool. There is no server to send a password to, and no other user's data to protect against you. The password exists only to prevent someone using your unlocked browser from casually opening the app — it is not a real security boundary.

**Do not reuse a password you use anywhere else.** Treat the Hisabs password as throwaway.

If anyone with access to your device's developer tools can read your `localStorage`, they can read your password. This is a limitation of any browser-only app and applies equally to Hisabs.

---

## What we don't do

- We don't collect your name, phone, or email — those stay in your browser.
- We don't show advertisements.
- We don't sell or share any information with anyone. There is no "anyone" — there is just the HTML file and your browser.
- We don't use cookies for tracking.
- We don't use Google Analytics, Facebook Pixel, or any third-party telemetry.
- We don't run code from a third-party CDN. (Some optional libraries like jsPDF are loaded only when you click Export to PDF, and they're loaded from a major CDN with no Hisabs identifier attached.)
- The "Continue with Google" button on the sign-in screen is a **local simulation**. It does not contact Google. It just lets you create an account that's marked as "Google-style" for visual flair.

---

## What this means in practice

**Different browser, different data.** If you sign in from a different device or browser, you will not see the books you made elsewhere. There is nothing to sync from.

**Clearing browser data wipes Hisabs.** "Clear site data," "clear cookies," "clear browsing history (including site data)," reinstalling your browser — any of these will erase everything. **Back up regularly.**

**Private/incognito mode is temporary.** Anything you create in a private window disappears when the window closes.

**Auto-backups are local too.** Every 30 minutes, Hisabs takes a snapshot of your data and keeps the last 3 in `localStorage`. These do not leave your device. They sit in the same browser storage as everything else. You can download them from **Settings → Data → Auto-backups**.

---

## Moving data between devices

The only way to move your data is to use the backup features yourself:

- **Settings → Data → Backup everything** downloads a JSON file with all your businesses.
- **Sidebar gear next to a business → Backup & restore** downloads one business at a time.
- To restore on another device, open Hisabs there, sign in, and use **Restore**.

Backup files **do not contain your password**. They contain your data and a minimal user identifier (name, login, account creation date). It is safe to email a backup to yourself or store it in cloud storage you control.

---

## Staff invites

When you invite a staff member, you store their phone or email in **your** browser, marked as a pending invite. When that person opens Hisabs in their own browser and signs in with the matching login, their copy of Hisabs (which has its own independent storage) will show the invite.

**This means the staff invite system only works if the same browser's `localStorage` contains both pieces of state.** In practice, this is a limitation: cross-device staff collaboration is not really possible without a backend, which Hisabs does not have. Use this feature for awareness, not for production team workflows.

---

## Hosting

If you access Hisabs through a hosted URL (for example, a Vercel deployment), the **HTML file itself** is served from that host. The hosting provider can see your IP address and your visit timestamp, the same as any website. The hosting provider **cannot** see the data you create inside Hisabs, because that data never leaves your browser.

If you self-host on a domain you control, even those access logs stay with you.

---

## Deletion

To erase everything Hisabs has stored:

- **Settings → Data → Danger zone → Delete my account and all data I own** removes your account and every business you own from your browser.
- Alternatively, clear browser data for the site (Settings → Privacy → Clear browsing data in most browsers, scoped to this site).

There is nothing to delete on any remote server, because nothing was ever stored on one.

---

## Children

Hisabs is general-purpose accounting software with no age-specific content. It is intended for individuals managing their own books or running their own small businesses. We do not knowingly collect data from anyone (because we do not collect data at all).

---

## Changes to this policy

If the underlying behavior of Hisabs changes — for instance, if a future version adds a backend — this policy will change to match. The "Last updated" date at the top will reflect any revision. Major changes will be called out in the app's user guide.

---

## Contact

Hisabs is a personal-use bookkeeping tool. There is no support team, no email address that resolves to a person, and no help desk. If you're running your own copy or a hosted instance, the owner of that copy is the only contact.

If you forked or are hosting Hisabs and want to take responsibility for a copy used by other people, replace this section with your own contact information.

---

## In one sentence

If something matters, back it up. The Data tab makes one click of work.
