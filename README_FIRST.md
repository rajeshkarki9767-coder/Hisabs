# Hisabs v89.6.1 — corrected release after re-check

```
index.html: 2492eb05d9c59d4bb0d8f4dd58ca726b
v89.6 (replaced):  139e32177f8f6dcf6e764fb95433f0c9
```

## What I missed in v89.6 (now fixed)

During re-check of v89.6 I found two real bugs in my own code:

### Bug 1 — The keyboard glitch root cause was wrong

v89.5 and v89.6 assumed the glitch came from realtime sync events
firing renderAll while the user typed. So I gated the realtime path.

The ACTUAL cause: on mobile, **opening the keyboard triggers a
viewport resize**, and the resize handler at line 15421 fires
`renderMain()` after 120ms. That destroys the input, keyboard
collapses, focus restore re-opens it. Visible glitch.

**Fix in v89.6.1:** the resize handler now checks if the resize
pattern matches "keyboard opened" (width unchanged + height changed +
input focused). If so, it skips the render.

### Bug 2 — Cloud-load functions were orphaned

v89.6 added `loadDistributionFromCloudOrLocal` and
`loadSplitPartiesFromCloudOrLocal` but **never called them**. So
managers wouldn't have seen owner changes anyway — reads still came
from localStorage.

**Fix in v89.6.1:** both functions are now called from the view
renderers (renderDistributionCard for distribution, renderAuditView
for split parties). When realtime events arrive, the re-render
triggers the cloud-load, which picks up the new data.

## Deploy order — UNCHANGED from v89.6

1. **Run the SQL migration first** if you haven't already
   (sql/v89.6_distribution_sync.sql)
2. Replace index.html
3. Commit + push

If you already ran the SQL for v89.6, you do NOT need to re-run it.
The SQL is unchanged. Only the client code changed.

## Smoke tests

1. **% prefix on Party input** — open Distribution → Parties. The %
   input has `%` symbol on the left inside the box.

2. **Keyboard glitch** — tap any Distribution input. Keyboard stays
   open continuously, no glitch. ← THIS IS THE REAL FIX

3. **Distribution sync** — as owner, edit a salary. As manager on
   a different device, open Distribution. You should see the update.
   ← THIS ALSO NOW WORKS

If the keyboard glitch still happens on your specific device, plug
your phone into your laptop, open Chrome DevTools remote debugging,
and tell me what shows up in the Console + Network when the glitch
happens. Could be a device-specific issue I can't reproduce.

## Files in this zip

```
hisabs_v89_6_1/
├── README_FIRST.md
├── V89_4_NOTES.md
├── .gitignore
├── index.html               ← v89.6.1 (REPLACES existing)
├── vercel.json              ← unchanged
├── api/cron/digest.js       ← unchanged
└── sql/
    └── v89.6_distribution_sync.sql   ← run if not already
```

## Honest note

I'm a bit embarrassed that v89.6 had these bugs. The first one
(resize → renderMain) I should have caught — it's literally listed
in the line numbers I dumped during analysis. The second one
(orphaned functions) I introduced in my own patch and forgot to wire.

Re-checking the source after building is the right discipline.
This time I'm more confident — but as always, the final word is
what happens on your phone.
