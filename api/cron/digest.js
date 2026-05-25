// api/cron/digest.js
//
// Vercel Cron edge function — fires once daily at 23:59 Asia/Kathmandu
// (= 18:14 UTC, no DST). Computes today's digest for every business,
// then sends a Web Push to every owner+manager who has a subscription.
//
// Schedule lives in vercel.json:
//   { "crons": [{ "path": "/api/cron/digest", "schedule": "14 18 * * *" }] }
//
// Required environment variables (set in Vercel project settings):
//   SUPABASE_URL              — https://sdovwbxqxvbbtpndrohd.supabase.co
//   SUPABASE_SERVICE_ROLE_KEY — service role key (Supabase Settings → API)
//   VAPID_PUBLIC_KEY          — same public key embedded in index.html
//   VAPID_PRIVATE_KEY         — the private half of the VAPID keypair
//   VAPID_SUBJECT             — "mailto:you@example.com" (your contact)
//   CRON_SECRET               — random string. Vercel sends this in the
//                               Authorization header on cron invocations;
//                               we reject anything without it so external
//                               callers can't trigger digests on demand.
//
// Schema assumed (from SUPABASE.sql in the project):
//   businesses(id, name, currency, owner_id, ...)
//   members(business_id, user_id, role, ...)
//   books(id, business_id, ...)
//   entries(id, book_id, date, type, amount, ...)
//   app_push_subscriptions(user_id, endpoint, p256dh, auth, ...)
//
// Notes:
//   - We use the service-role key so we can read across all businesses
//     in one cron run. Never expose this key in the browser.
//   - VAPID-signed Web Push is sent directly from this function via
//     the `web-push` npm package.
//   - If a push subscription returns 404/410 (subscription gone), we
//     delete it so the table doesn't accumulate stale rows.

import webpush from 'web-push';

export const config = { runtime: 'nodejs' };

// =========================================================================
// helpers
// =========================================================================
const SUPABASE_URL = process.env.SUPABASE_URL;
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

function authHeaders() {
  return {
    'apikey': SERVICE_KEY,
    'Authorization': `Bearer ${SERVICE_KEY}`,
    'Content-Type': 'application/json',
  };
}

async function supaSelect(path) {
  const r = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, { headers: authHeaders() });
  if (!r.ok) throw new Error(`Supabase select ${path} -> ${r.status}: ${await r.text()}`);
  return r.json();
}

async function supaDelete(path) {
  const r = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    method: 'DELETE',
    headers: authHeaders(),
  });
  return r.ok;
}

// Asia/Kathmandu = UTC+5:45. Returns today's Kathmandu date as YYYY-MM-DD.
function kathmanduTodayYYYYMMDD() {
  const offsetMs = (5 * 60 + 45) * 60 * 1000;
  const d = new Date(Date.now() + offsetMs);
  const y = d.getUTCFullYear();
  const m = String(d.getUTCMonth() + 1).padStart(2, '0');
  const dd = String(d.getUTCDate()).padStart(2, '0');
  return `${y}-${m}-${dd}`;
}

// Currency display shim — mirrors the browser logic enough for the
// digest text. NPR → "Rs", USD → "$", anything else → its 3-letter code.
function currencyDisplay(code) {
  const map = {
    NPR: 'Rs', INR: '₹', USD: '$', EUR: '€', GBP: '£',
    JPY: '¥', AUD: 'A$', CAD: 'C$', SGD: 'S$', AED: 'AED',
  };
  return map[code] || code || 'Rs';
}

function fmtAmount(n) {
  const v = Number(n) || 0;
  return v.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

function formatDigest(biz, summary) {
  const cur = currencyDisplay(biz.currency);
  if (summary.count === 0) {
    return `${biz.name} — Today: no entries recorded.`;
  }
  const sign = summary.net >= 0 ? '+' : '−';
  return `${biz.name} — Today: ${summary.count} ${summary.count === 1 ? 'entry' : 'entries'}, `
       + `${cur} ${fmtAmount(summary.cashIn)} in − ${cur} ${fmtAmount(summary.cashOut)} out `
       + `= ${cur} ${sign}${fmtAmount(Math.abs(summary.net))} net`;
}

// =========================================================================
// handler
// =========================================================================
export default async function handler(req, res) {
  // CRON_SECRET gate — Vercel sends this in Authorization on scheduled
  // invocations. Anything else gets bounced.
  const expected = process.env.CRON_SECRET;
  if (expected) {
    const got = req.headers['authorization'] || '';
    if (got !== `Bearer ${expected}`) {
      return res.status(401).json({ ok: false, error: 'unauthorized' });
    }
  }

  // Sanity-check env
  if (!SUPABASE_URL || !SERVICE_KEY) {
    return res.status(500).json({ ok: false, error: 'SUPABASE_URL or SERVICE_ROLE_KEY missing' });
  }
  if (!process.env.VAPID_PUBLIC_KEY || !process.env.VAPID_PRIVATE_KEY) {
    return res.status(500).json({ ok: false, error: 'VAPID keys missing' });
  }

  webpush.setVapidDetails(
    process.env.VAPID_SUBJECT || 'mailto:owner@hisabs.app',
    process.env.VAPID_PUBLIC_KEY,
    process.env.VAPID_PRIVATE_KEY,
  );

  const today = kathmanduTodayYYYYMMDD();
  const stats = { businesses: 0, subscriptionsSent: 0, deliveryErrors: 0, stalePruned: 0 };

  try {
    // 1) Pull all businesses
    const businesses = await supaSelect('businesses?select=id,name,currency,owner_id');

    // 2) Pull all members (we'll filter to owner+manager per-biz)
    const members = await supaSelect('members?select=business_id,user_id,role&role=in.(owner,manager)');

    // Index members by business
    const membersByBiz = new Map();
    for (const m of members) {
      if (!membersByBiz.has(m.business_id)) membersByBiz.set(m.business_id, []);
      membersByBiz.get(m.business_id).push(m);
    }

    // 3) Pull all books (we need book_id → business_id mapping)
    const books = await supaSelect('books?select=id,business_id');
    const bizByBook = new Map(books.map(b => [b.id, b.business_id]));
    const booksByBiz = new Map();
    for (const b of books) {
      if (!booksByBiz.has(b.business_id)) booksByBiz.set(b.business_id, []);
      booksByBiz.get(b.business_id).push(b.id);
    }

    // 4) Pull today's entries only
    const entries = await supaSelect(
      `entries?select=book_id,type,amount&date=eq.${today}`
    );

    // 5) Per-business summaries
    const summariesByBiz = new Map();
    for (const biz of businesses) {
      const bookIds = new Set(booksByBiz.get(biz.id) || []);
      let count = 0, cashIn = 0, cashOut = 0;
      for (const e of entries) {
        if (!bookIds.has(e.book_id)) continue;
        count += 1;
        const amt = Number(e.amount) || 0;
        if (e.type === 'in') cashIn += amt;
        else cashOut += amt;
      }
      summariesByBiz.set(biz.id, { count, cashIn, cashOut, net: cashIn - cashOut });
    }

    // 6) Per-user push subscriptions
    const subs = await supaSelect('app_push_subscriptions?select=user_id,endpoint,p256dh,auth');
    const subsByUser = new Map();
    for (const s of subs) {
      if (!subsByUser.has(s.user_id)) subsByUser.set(s.user_id, []);
      subsByUser.get(s.user_id).push(s);
    }

    // 7) For each biz, push digest to each owner+manager's subscriptions
    for (const biz of businesses) {
      const summary = summariesByBiz.get(biz.id);
      const text = formatDigest(biz, summary);
      const recipients = membersByBiz.get(biz.id) || [];
      // Also include the owner row explicitly in case `members` only
      // tracks invited members and not the original owner.
      const targetUserIds = new Set(recipients.map(r => r.user_id));
      if (biz.owner_id) targetUserIds.add(biz.owner_id);

      let sentForBiz = 0;
      for (const uid of targetUserIds) {
        const userSubs = subsByUser.get(uid) || [];
        for (const sub of userSubs) {
          const subscription = {
            endpoint: sub.endpoint,
            keys: { p256dh: sub.p256dh, auth: sub.auth },
          };
          const payload = JSON.stringify({
            title: 'Hisabs — daily summary',
            body: text,
            tag: `hisabs-digest-${biz.id}-${today}`,
            // Optional URL the SW will navigate to on click
            url: '/',
          });
          try {
            await webpush.sendNotification(subscription, payload, { TTL: 23 * 3600 });
            sentForBiz += 1;
            stats.subscriptionsSent += 1;
          } catch (err) {
            // 404/410 means the subscription is dead; prune it.
            const code = err && err.statusCode;
            if (code === 404 || code === 410) {
              // Endpoint is opaque — best to match on it directly
              const enc = encodeURIComponent(sub.endpoint);
              try {
                const ok = await supaDelete(`app_push_subscriptions?endpoint=eq.${enc}`);
                if (ok) stats.stalePruned += 1;
              } catch (_) {}
            } else {
              stats.deliveryErrors += 1;
              console.warn(`Push to user ${uid} failed (${code}):`, err.message || err);
            }
          }
        }
      }
      if (sentForBiz > 0) stats.businesses += 1;
    }

    return res.status(200).json({
      ok: true,
      date: today,
      ...stats,
    });
  } catch (e) {
    console.error('Digest cron failed:', e);
    return res.status(500).json({ ok: false, error: e.message || String(e) });
  }
}
