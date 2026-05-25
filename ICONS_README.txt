APP ICONS — add your own here.

index.html and manifest.webmanifest expect two PNG icons at these exact paths:

    icons/icon-192.png   (192 x 192 px)
    icons/icon-512.png   (512 x 512 px)

Create an "icons" folder at the project root and place your two icons in it
using those exact filenames. No code changes needed — the app already
references these paths (favicon, apple-touch-icon, PWA manifest, and
notification icon).

For best PWA results: use square PNGs with a bit of padding so the "maskable"
crop on Android doesn't clip your logo. 512x512 is the master; 192x192 is the
smaller variant.

(The placeholder icons that shipped earlier were removed at your request.)
