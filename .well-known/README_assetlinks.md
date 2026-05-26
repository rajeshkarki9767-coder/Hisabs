# assetlinks.json — what to do before Play Store submission

This file lives at `.well-known/assetlinks.json` and, once live, will be served at:

    https://hisabs.app/.well-known/assetlinks.json

`vercel.json` already routes this path with `Content-Type: application/json`,
no-cache, and `Access-Control-Allow-Origin: *`, so once the file is deployed it
will serve correctly.

## ⚠️ IT IS NOT FINISHED YET — two placeholders must be replaced

The committed file contains PLACEHOLDER values that will NOT verify your app
until you replace them with the real values from your Play Store build:

1. **`package_name`** — currently `app.hisabs.twa`.
   Replace with the actual Android package name you choose when building the TWA
   (Bubblewrap/PWABuilder asks for this; it must match your Play Console listing).

2. **`sha256_cert_fingerprints`** — currently `REPLACE_WITH_YOUR_SHA256_FINGERPRINT`.
   Replace with your app's real SHA-256 signing-key fingerprint. You get this from
   EITHER:
     • Bubblewrap/PWABuilder output when you generate the signed APK/AAB, OR
     • Google Play Console → your app → Setup → App integrity → App signing key
       certificate → "SHA-256 certificate fingerprint" (recommended: use the
       **Play App Signing** key fingerprint, since Google re-signs your app).
   Format is colon-separated hex, e.g.
     "AB:CD:12:34:...:EF"

   You can list MORE THAN ONE fingerprint (e.g. both your upload key and the
   Play App Signing key) — just add them as separate quoted strings in the array.

## Why it matters
When a user opens the Play Store (TWA) version of Hisabs, Android fetches this
file to confirm the app is authorised to open hisabs.app full-screen WITHOUT the
browser address bar. With wrong/placeholder values, the TWA will show a Chrome
address bar (or fail Digital Asset Links verification).

## How to verify after filling it in
1. Deploy so the file is live at the URL above.
2. Check it loads as JSON in a browser.
3. Use Google's tester:
   https://developers.google.com/digital-asset-links/tools/generator
   or the statement-list test:
   https://digitalassetlinks.googleapis.com/v1/statements:list?source.web.site=https://hisabs.app&relation=delegate_permission/common.handle_all_urls

## Until then
Leaving the placeholder file in place is harmless for the normal web/PWA app —
it only affects the Play Store TWA verification, which you complete at packaging
time.
