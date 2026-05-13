// ============================================================
// Hisabs Service Worker
// ============================================================
// Strategy by request type:
//   - Supabase API & realtime → NEVER intercept (always network)
//   - index.html / navigation  → network-first, fall back to cache
//   - vendor JS, icons, manifest → cache-first (immutable)
//   - everything else (CSS, fonts) → stale-while-revalidate
//
// Versioned cache name. Bump CACHE_VERSION any time the app shell
// changes meaningfully so old caches get purged on activate.
// ============================================================

const CACHE_VERSION = 'hisabs-v1';
const APP_SHELL = [
  './',
  './index.html',
  './manifest.webmanifest',
  './vendor/supabase.umd.js',
  './vendor/jspdf.umd.min.js',
  './vendor/jspdf.plugin.autotable.min.js',
  './icons/icon-192.png',
  './icons/icon-512.png',
  './icons/icon-maskable-512.png',
];

self.addEventListener('install', (event) => {
  // Pre-cache the app shell so the very first offline page-load works.
  // Failures are non-fatal: if one vendor file 404s the install still
  // completes and the page just won't be fully offline-ready.
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE_VERSION);
    await Promise.all(APP_SHELL.map(async (url) => {
      try { await cache.add(url); } catch (e) { /* ignore individual failures */ }
    }));
    // Take over immediately on first install so the user sees offline
    // capability on their current page load, not just the next one.
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', (event) => {
  // Delete every cache that isn't ours. Prevents old versions from
  // serving stale code after a deploy.
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.map((k) => (k === CACHE_VERSION ? null : caches.delete(k))));
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;             // never cache writes
  const url = new URL(req.url);

  // 1. Never intercept Supabase calls — they MUST hit the network.
  //    Caching auth, postgrest, or realtime responses would be a
  //    security and correctness disaster.
  if (
    url.hostname.endsWith('.supabase.co') ||
    url.hostname.endsWith('.supabase.in')   ||
    url.protocol === 'wss:' || url.protocol === 'ws:'
  ) {
    return; // default browser fetch
  }

  // 2. Cross-origin: don't cache at all. Lets fonts.googleapis.com etc.
  //    handle their own caching headers.
  if (url.origin !== self.location.origin) {
    return;
  }

  // 3. Navigation requests (i.e. loading the page itself): network-first.
  //    This guarantees that as soon as you deploy a new index.html, the
  //    next page load fetches it. Falling back to cache only on network
  //    failure so the app still opens offline.
  if (req.mode === 'navigate') {
    event.respondWith((async () => {
      try {
        const fresh = await fetch(req);
        const cache = await caches.open(CACHE_VERSION);
        cache.put(req, fresh.clone()).catch(() => {});
        return fresh;
      } catch (e) {
        const cached = await caches.match(req);
        if (cached) return cached;
        // Last-resort: match the cached root.
        const root = await caches.match('./index.html');
        if (root) return root;
        throw e;
      }
    })());
    return;
  }

  // 4. Static vendor files and icons: cache-first (these are versioned
  //    by filename so they never change; the immutable Cache-Control
  //    header in vercel.json reinforces this).
  if (
    url.pathname.startsWith('/vendor/') ||
    url.pathname.startsWith('/icons/')
  ) {
    event.respondWith((async () => {
      const cached = await caches.match(req);
      if (cached) return cached;
      try {
        const fresh = await fetch(req);
        const cache = await caches.open(CACHE_VERSION);
        cache.put(req, fresh.clone()).catch(() => {});
        return fresh;
      } catch (e) { throw e; }
    })());
    return;
  }

  // 5. Default: stale-while-revalidate. Serve cache if present, but
  //    update the cache from network in the background.
  event.respondWith((async () => {
    const cache = await caches.open(CACHE_VERSION);
    const cached = await cache.match(req);
    const network = fetch(req).then((resp) => {
      // Only cache OK responses. Avoid caching opaque or error responses.
      if (resp && resp.ok) cache.put(req, resp.clone()).catch(() => {});
      return resp;
    }).catch(() => null);
    return cached || (await network) || Response.error();
  })());
});

// Allow the page to message the SW asking it to skip waiting (useful
// if we ever build an "update available, reload" prompt).
self.addEventListener('message', (event) => {
  if (event.data === 'SKIP_WAITING') self.skipWaiting();
});
