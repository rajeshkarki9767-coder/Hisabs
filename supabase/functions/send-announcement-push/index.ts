// ============================================================
// Hisabs Edge Function: send-announcement-push
// ============================================================
// Fans out a Web Push notification to every member of the business
// when a new announcement is posted. Called by the client right
// after the announcement row syncs to Supabase.
//
// Body shape (JSON):
//   {
//     announcement_id: "ann_xxx"
//   }
//
// We DON'T trust client-supplied body content — the function looks up
// the announcement row using the service role, verifies the caller is
// the author (owner of the business), then fetches every push
// subscription for every member of that business and sends the push.
//
// Uses npm:web-push for VAPID signing + payload encryption.
// Requires Supabase secrets:
//   - VAPID_PUBLIC_KEY
//   - VAPID_PRIVATE_KEY
//   - VAPID_SUBJECT  (e.g. "mailto:you@example.com")
// ============================================================

// deno-lint-ignore-file no-explicit-any
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';
import webpush from 'npm:web-push@3.6.7';

declare const Deno: { env: { get(k: string): string | undefined }; serve: (h: (r: Request) => Response | Promise<Response>) => void };

const SUPABASE_URL          = Deno.env.get('SUPABASE_URL')             ?? '';
const SUPABASE_ANON_KEY     = Deno.env.get('SUPABASE_ANON_KEY')        ?? '';
const SUPABASE_SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
const VAPID_PUBLIC_KEY      = Deno.env.get('VAPID_PUBLIC_KEY')         ?? '';
const VAPID_PRIVATE_KEY     = Deno.env.get('VAPID_PRIVATE_KEY')        ?? '';
const VAPID_SUBJECT         = Deno.env.get('VAPID_SUBJECT')            ?? 'mailto:admin@hisabs.app';

const ALLOWED_ORIGINS = new Set([
  'https://hisabs.vercel.app',
]);
function corsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get('Origin') ?? '';
  const allowed = ALLOWED_ORIGINS.has(origin) ? origin : '';
  return {
    'Access-Control-Allow-Origin': allowed,
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Vary': 'Origin',
  };
}

if (VAPID_PUBLIC_KEY && VAPID_PRIVATE_KEY) {
  try {
    (webpush as any).setVapidDetails(VAPID_SUBJECT, VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY);
  } catch (e) {
    console.error('VAPID setup failed:', e);
  }
}

Deno.serve(async (req: Request): Promise<Response> => {
  const CORS_HEADERS = corsHeaders(req);
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS_HEADERS });
  if (req.method !== 'POST') return jsonResp(CORS_HEADERS, { error: 'Method not allowed' }, 405);

  const authHeader = req.headers.get('Authorization') ?? req.headers.get('authorization');
  if (!authHeader?.startsWith('Bearer ')) return jsonResp(CORS_HEADERS, { error: 'Unauthorized' }, 401);
  const accessToken = authHeader.slice('Bearer '.length).trim();
  if (!accessToken) return jsonResp(CORS_HEADERS, { error: 'Unauthorized' }, 401);

  if (!SUPABASE_SERVICE_ROLE) return jsonResp(CORS_HEADERS, { error: 'Server misconfigured' }, 500);
  if (!VAPID_PUBLIC_KEY || !VAPID_PRIVATE_KEY) {
    return jsonResp(CORS_HEADERS, { error: 'VAPID keys not configured. Set VAPID_PUBLIC_KEY and VAPID_PRIVATE_KEY in Supabase secrets.' }, 500);
  }

  const verifyClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
  const { data: userData, error: userErr } = await verifyClient.auth.getUser(accessToken);
  if (userErr || !userData?.user?.id) {
    return jsonResp(CORS_HEADERS, { error: 'Unauthorized' }, 401);
  }
  const callerUserId = userData.user.id;

  let body: any;
  try { body = await req.json(); }
  catch (_) { return jsonResp(CORS_HEADERS, { error: 'Bad JSON' }, 400); }

  const annId = String(body?.announcement_id || '');
  if (!annId) return jsonResp(CORS_HEADERS, { error: 'Missing announcement_id' }, 400);

  const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // Load the announcement.
  const { data: ann, error: annErr } = await adminClient
    .from('app_announcements')
    .select('id, business_id, author_id, author_name, body, important, created_at')
    .eq('id', annId)
    .maybeSingle();
  if (annErr) { console.error('ann lookup error', annErr); return jsonResp(CORS_HEADERS, { error: 'Lookup failed' }, 500); }
  if (!ann) return jsonResp(CORS_HEADERS, { error: 'Announcement not found' }, 404);

  // Verify the caller is the announcement's author (don't let a random
  // signed-in user trigger pushes for someone else's announcement).
  if (ann.author_id && ann.author_id !== callerUserId) {
    return jsonResp(CORS_HEADERS, { error: 'Forbidden' }, 403);
  }

  // Look up the business to get its name (for notification title).
  const { data: biz } = await adminClient
    .from('app_businesses')
    .select('id, name, owner_id')
    .eq('id', ann.business_id)
    .maybeSingle();
  const bizName = biz?.name || 'Hisabs';

  // Gather every user that should receive the push:
  //   - the business owner (if not the author)
  //   - every accepted member (if their user_id is set)
  // (We exclude the author so they don't get a push for their own post.)
  const recipientIds = new Set<string>();
  if (biz?.owner_id && biz.owner_id !== callerUserId) {
    recipientIds.add(biz.owner_id);
  }
  const { data: members } = await adminClient
    .from('app_members')
    .select('user_id, status')
    .eq('business_id', ann.business_id)
    .eq('status', 'accepted');
  for (const m of (members || [])) {
    if (m.user_id && m.user_id !== callerUserId) recipientIds.add(m.user_id);
  }

  if (recipientIds.size === 0) {
    return jsonResp(CORS_HEADERS, { ok: true, sent: 0, note: 'No recipients with linked accounts.' });
  }

  // Fetch every push subscription for the recipient set.
  const { data: subs, error: subErr } = await adminClient
    .from('app_push_subscriptions')
    .select('id, endpoint, p256dh, auth_key, user_id')
    .in('user_id', Array.from(recipientIds));
  if (subErr) { console.error('subs lookup error', subErr); return jsonResp(CORS_HEADERS, { error: 'Subs lookup failed' }, 500); }
  if (!subs || subs.length === 0) {
    return jsonResp(CORS_HEADERS, { ok: true, sent: 0, note: 'No push subscriptions for recipients.' });
  }

  // Build the payload. Service worker receives this and constructs the
  // OS notification. Keep the body short — some push services cap at
  // 4 KB.
  const payload = JSON.stringify({
    title: ann.important
      ? `⚠ ${bizName} — Important`
      : `${bizName} — Announcement`,
    body: String(ann.body || '').slice(0, 220),
    important: !!ann.important,
    announcement_id: ann.id,
    author_name: ann.author_name || 'Owner',
  });

  // Send with limited parallelism — 5 concurrent. web-push handles VAPID
  // signing + payload encryption. We collect dead endpoints (410 Gone)
  // and delete them so we don't keep retrying.
  const deadSubIds: string[] = [];
  let sent = 0;
  async function sendOne(s: any): Promise<void> {
    try {
      await (webpush as any).sendNotification(
        { endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth_key } },
        payload,
        { TTL: 24 * 60 * 60 },  // push service may hold for 24h if device offline
      );
      sent++;
    } catch (e: any) {
      const code = e?.statusCode;
      if (code === 404 || code === 410) {
        // Subscription is dead — clean up.
        deadSubIds.push(s.id);
      } else {
        console.warn('push send failed', code, e?.body || e?.message);
      }
    }
  }
  // Concurrency-limited fan-out.
  const queue = subs.slice();
  async function worker() {
    while (queue.length) {
      const s = queue.shift();
      if (s) await sendOne(s);
    }
  }
  await Promise.all([worker(), worker(), worker(), worker(), worker()]);

  // Garbage-collect dead subscriptions.
  if (deadSubIds.length) {
    await adminClient.from('app_push_subscriptions').delete().in('id', deadSubIds);
  }

  return jsonResp(CORS_HEADERS, { ok: true, sent, dead: deadSubIds.length });
});

function jsonResp(corsHdrs: Record<string, string>, body: any, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHdrs, 'Content-Type': 'application/json' },
  });
}
