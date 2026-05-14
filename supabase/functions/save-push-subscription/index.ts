// ============================================================
// Hisabs Edge Function: save-push-subscription
// ============================================================
// Stores a browser's Web Push subscription so the server can fan
// out push notifications later. Client calls this after the user
// grants notification permission and PushManager.subscribe()
// returns a subscription object.
//
// Body shape (JSON):
//   {
//     endpoint: "https://fcm.googleapis.com/fcm/send/...",
//     keys: { p256dh: "...", auth: "..." },
//     userAgent?: "Mozilla/5.0 ..."
//   }
//
// Idempotent: re-subscribing with the same endpoint updates the
// existing row. Different endpoints (e.g. after browser data
// clear) create a new row.
// ============================================================

// deno-lint-ignore-file no-explicit-any
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';

declare const Deno: { env: { get(k: string): string | undefined }; serve: (h: (r: Request) => Response | Promise<Response>) => void };

const SUPABASE_URL          = Deno.env.get('SUPABASE_URL')             ?? '';
const SUPABASE_ANON_KEY     = Deno.env.get('SUPABASE_ANON_KEY')        ?? '';
const SUPABASE_SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

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

Deno.serve(async (req: Request): Promise<Response> => {
  const CORS_HEADERS = corsHeaders(req);
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS_HEADERS });
  if (req.method !== 'POST') return jsonResp(CORS_HEADERS, { error: 'Method not allowed' }, 405);

  const authHeader = req.headers.get('Authorization') ?? req.headers.get('authorization');
  if (!authHeader?.startsWith('Bearer ')) return jsonResp(CORS_HEADERS, { error: 'Unauthorized' }, 401);
  const accessToken = authHeader.slice('Bearer '.length).trim();
  if (!accessToken) return jsonResp(CORS_HEADERS, { error: 'Unauthorized' }, 401);

  const verifyClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
  const { data: userData, error: userErr } = await verifyClient.auth.getUser(accessToken);
  if (userErr || !userData?.user?.id) {
    return jsonResp(CORS_HEADERS, { error: 'Unauthorized' }, 401);
  }
  const userId = userData.user.id;

  if (!SUPABASE_SERVICE_ROLE) {
    return jsonResp(CORS_HEADERS, { error: 'Server misconfigured' }, 500);
  }

  let body: any;
  try { body = await req.json(); }
  catch (_) { return jsonResp(CORS_HEADERS, { error: 'Bad JSON' }, 400); }

  const endpoint = String(body?.endpoint || '');
  const p256dh   = String(body?.keys?.p256dh || '');
  const authKey  = String(body?.keys?.auth || '');
  if (!endpoint || !p256dh || !authKey) {
    return jsonResp(CORS_HEADERS, { error: 'Missing subscription fields' }, 400);
  }
  // Sanity-check endpoint URL — must be https.
  try {
    const u = new URL(endpoint);
    if (u.protocol !== 'https:') throw new Error('Insecure endpoint');
  } catch (_) {
    return jsonResp(CORS_HEADERS, { error: 'Invalid endpoint' }, 400);
  }

  const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // Upsert by endpoint (unique). If this exact endpoint already exists
  // for a different user (rare — browser data shared somehow), we steal
  // it for the authenticated user.
  const userAgent = String(body?.userAgent || req.headers.get('User-Agent') || '').slice(0, 500);
  const now = new Date().toISOString();
  const id = 'pus_' + Math.random().toString(36).slice(2, 10) + Math.random().toString(36).slice(2, 10);

  const { error: upsertErr } = await adminClient
    .from('app_push_subscriptions')
    .upsert({
      id,
      user_id: userId,
      endpoint,
      p256dh,
      auth_key: authKey,
      user_agent: userAgent,
      created_at: now,
      updated_at: now,
    }, { onConflict: 'endpoint' });

  if (upsertErr) {
    console.error('save-push-subscription upsert error:', upsertErr);
    return jsonResp(CORS_HEADERS, { error: 'Could not save subscription' }, 500);
  }

  return jsonResp(CORS_HEADERS, { ok: true });
});

function jsonResp(corsHdrs: Record<string, string>, body: any, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHdrs, 'Content-Type': 'application/json' },
  });
}
