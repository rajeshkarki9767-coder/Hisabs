# Hisabs v89.30.2 — CSP audio fix

```
index.html:  7174d13bc3a1f2ab7a8f9c7544f106e7 (unchanged from v89.30.1)
vercel.json: UPDATED — adds media-src directive to CSP
```

## What changed in this revision

### Console error fix: sounds blocked by CSP

Browser console showed:
```
Loading media from 'data:audio/wav;base64,...' violates the following CSP
directive: "default-src 'self'". Note that 'media-src' was not explicitly
set, so 'default-src' is used as a fallback. The action has been blocked.
```

**Cause**: The CSP in vercel.json had no `media-src` directive, so it
fell back to `default-src 'self'`, which blocks `data:` URIs. Hisabs
embeds 4 sound effects (cash-in, cash-out, delete, announcement) as
inline base64 `data:audio/wav` — they were being blocked entirely.

**Fix**: Added `media-src 'self' data: blob:` to the CSP in vercel.json.

After redeploy, sounds will work in the browser.

### Other console messages — diagnosed

**1. Google Analytics blocked by CSP** ⚠️ Investigate source
```
Connecting to '<URL>' violates CSP directive: "connect-src 'self' ..."
Fetch API cannot load https://www.google-analytics.com/mp/collect...
```

The index.html has ZERO Google Analytics code (verified by grep).
The blocked call must come from one of:
- A browser extension you have installed
- A cached old build from before you cleaned analytics
- Some 3rd-party tool injection

**The CSP is correctly blocking it** — protecting your users' privacy.
No code change needed. To identify the source:

1. Test in Incognito mode with no extensions → if errors disappear,
   it's an extension
2. If still there in Incognito → check Network tab to see which page
   resource is loading the GA script

**2. Beforeinstallprompt banner not shown** ✅ Normal
This is your code intentionally suppressing Chrome's default install
banner so you can show your own custom prompt later. Not an error.

**3. Realtime: SUBSCRIBED** ✅ Success log
Your realtime sync is connecting properly.

**4. AudioContext autoplay block** ✅ Expected
Browsers require user interaction before audio plays. Your
`unlockEntrySound()` handles this — it tries on page load (fails
silently), then succeeds after first user click. No action needed.

## Final CSP (vercel.json)

```
default-src 'self';
script-src 'self' 'unsafe-inline' blob:;
script-src-elem 'self' 'unsafe-inline' blob:;
worker-src 'self' blob:;
style-src 'self' 'unsafe-inline' https://fonts.googleapis.com;
font-src 'self' https://fonts.gstatic.com data:;
img-src 'self' data: blob:;
media-src 'self' data: blob:;             ← NEW (v89.30.2)
connect-src 'self' https://*.supabase.co wss://*.supabase.co;
frame-ancestors 'self';
base-uri 'self';
form-action 'self';
manifest-src 'self';
upgrade-insecure-requests
```

## All v89.30 fixes still intact

Everything from v89.30.1 preserved — only vercel.json changed.

## Deploy

```bash
cd ~/Documents/GitHub/hisabs
cp ~/Downloads/hisabs_v89_27_final/vercel.json ./vercel.json
# index.html unchanged from v89.30.1 — no need to copy again unless you skipped it
git add vercel.json
git commit -m "v89.30.2: add media-src to CSP for inline audio data URIs"
git push
```

After Vercel deploys (~30s), test in browser:
1. Hard reload (Cmd+Shift+R / Ctrl+Shift+R) to bypass cache
2. Open DevTools → Console → make a cash-in entry
3. The CSP media error should be gone, sound should play after first
   click on the page (autoplay rule)

