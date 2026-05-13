// ============================================================
// Hisabs Edge Function: revoke-my-session
// ============================================================
// Revokes (deletes) a specific session by its UUID, but ONLY if it
// belongs to the calling user. Used by Settings → Data → Devices for
// per-device "Sign out" buttons.
//
// Request body: { session_id: "uuid" }
//
// Security:
//   1. JWT validates the caller
//   2. CORS allowlist restricts browser callers to the Hisabs origin
//   3. We confirm the session row's user_id matches the caller
//   4. Only then do we delete it
//
// A caller can only ever revoke their own sessions. The function never
// reveals whether a foreign session exists — same response shape for
// "no such session" and "not yours" to prevent enumeration.
// ============================================================

// deno-lint-ignore-file no-explicit-any
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';

declare const Deno: { env: { get(k: string): string | undefined }; serve: (h: (r: Request) => Response | Promise<Response>) => void };

const SUPABASE_URL          = Deno.env.get('SUPABASE_URL')             ?? '';
const SUPABASE_ANON_KEY     = Deno.env.get('SUPABASE_ANON_KEY')        ?? '';
const SUPABASE_SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

// CORS allowlist — see delete-self-account for explanation.
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

  let body: any = null;
  try { body = await req.json(); } catch (_) { return jsonResp(CORS_HEADERS, { error: 'Bad request' }, 400); }
  const sessionId = String(body?.session_id ?? '').trim();
  if (!sessionId || !/^[0-9a-f-]{32,36}$/i.test(sessionId)) {
    return jsonResp(CORS_HEADERS, { error: 'Bad request' }, 400);
  }

  const verifyClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
  const { data: userData, error: userErr } = await verifyClient.auth.getUser(accessToken);
  if (userErr || !userData?.user?.id) {
    return jsonResp(CORS_HEADERS, { error: 'Unauthorized' }, 401);
  }
  const userId = userData.user.id;

  if (!SUPABASE_SERVICE_ROLE) {
    console.error('Server misconfigured: missing SUPABASE_SERVICE_ROLE_KEY');
    return jsonResp(CORS_HEADERS, { error: 'Server error' }, 500);
  }
  const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // Single DELETE constrained by both id AND user_id. If the session
  // doesn't exist OR doesn't belong to the caller, zero rows match
  // and the result is the same — no enumeration possible.
  const { error: delErr, count } = await adminClient
    .schema('auth')
    .from('sessions')
    .delete({ count: 'exact' })
    .eq('id', sessionId)
    .eq('user_id', userId);
  if (delErr) {
    console.error('revoke-my-session delete failed', sessionId, delErr);
    return jsonResp(CORS_HEADERS, { error: 'Delete failed' }, 500);
  }
  if (!count) {
    // Either the session never existed or it isn't this user's. Same
    // response for both to prevent enumeration of session IDs.
    return jsonResp(CORS_HEADERS, { error: 'Not found' }, 404);
  }

  return jsonResp(CORS_HEADERS, { ok: true, revoked_session_id: sessionId });
});

function jsonResp(corsHdrs: Record<string, string>, body: any, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHdrs, 'Content-Type': 'application/json' },
  });
}
