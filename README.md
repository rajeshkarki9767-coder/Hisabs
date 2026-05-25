# Hisabs

A quiet, careful place to keep your books.

Hisabs is a local-first bookkeeping web app. Everything runs in your browser — no servers, no accounts on remote systems, no analytics.

## What it does

- Multiple businesses, each with their own books, parties, categories, and accounts
- Cash in / cash out entries with running balances
- Period filters (this month / all time / custom)
- Owner-only Audit view with month-scoped expenses, accounts, profit, and net profit
- Profit-split + currency-conversion calculator on Audit
- Hide/archive accounts without losing historical data
- Staff and viewer roles with permission gating
- Backup and restore (per business or everything at once); rolling auto-backup
- Dark mode + accent color themes
- Installable as a PWA on phone and desktop
- Forgot-password reset (local-only; for now)

## Project structure

```
hisabs/
├── index.html                    # The app — single HTML file with all CSS + JS
├── manifest.webmanifest          # PWA manifest (referenced by index.html)
├── icons/
│   ├── icon-192.png              # PWA icon, standard
│   ├── icon-512.png              # PWA icon, large
│   ├── icon-maskable-512.png     # PWA icon for adaptive (round/squircle) shapes
│   ├── icon.svg                  # Source for the standard icons
│   └── icon-maskable.svg         # Source for the maskable icon
├── vendor/
│   ├── jspdf.umd.min.js          # PDF export library (self-hosted, was CDN)
│   └── jspdf.plugin.autotable.min.js  # PDF table plugin
├── PRIVACY.md                    # Privacy policy
├── README.md                     # This file
├── vercel.json                   # Static-site config + security headers
└── .gitignore
```

The third-party libraries are **self-hosted under `vendor/`** rather than loaded from a CDN. This eliminates supply-chain risk (a compromised CDN can't inject code into your app) and makes the app fully offline-capable once installed.

## How to use

Open `index.html` in any modern browser. Sign up, create your first business, start adding entries.

For PWA install on a phone, the app has to be served over HTTPS (or `localhost`) — opening from `file://` works for using it but won't show the "Install" prompt. Deploy to Vercel (see below) for the install option.

## Deployment

This is a static site. To host it:

- **Locally**: open `index.html` directly. Works on `file://`.
- **Vercel**: import this repo. No build configuration needed. Vercel will serve everything as-is and applies the security headers in `vercel.json`.
- **GitHub Pages**: enable Pages in repo settings, point at `main` branch root.
- **Any static host**: upload the whole folder. Preserve the directory structure (`vendor/`, `icons/`, `manifest.webmanifest`).

## Privacy

Everything stays in your browser, in `localStorage`. There is no server. Different browser, different data. Clearing your browser data wipes Hisabs. Back up regularly — the Data tab in Settings makes that one click.

See [PRIVACY.md](./PRIVACY.md) for the full privacy policy.

## Limitations

- **No sync between devices.** Each browser is its own island. Use the Backup feature in Settings → Data to move data between devices.
- **No real authentication.** The "Continue with Google" button is simulated. Passwords are stored in `localStorage`. This is a personal/single-device app — not multi-user web infrastructure.
- **Staff invites work in theory, not in practice across devices.** Without a server, an invite stored in your browser can't be seen by anyone else's browser. This is a real limitation of the no-backend architecture.

## License

Personal project. Use it however you'd like.
