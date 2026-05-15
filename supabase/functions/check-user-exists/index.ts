// ============================================================
// Hisabs Edge Function: check-user-exists
// ============================================================
// Returns whether an email address already has a Hisabs/Supabase
// account. Used by the Team page to prevent inviting random
// emails that never signed up — those invites would just sit
// pending forever because the invitee has no way to see them.
//
// We deliberately do NOT expose any user details (name, id, etc).
// The response is { exists: true } or { exists: false } only.
// It IS a user-enumeration oracle by nature, but it's gated
// behind a valid auth token (you must already be signed in)
// and the inviter is going to type the email regardless. A
// signed-in member already has stronger lookups available via
// app_members in the database.
//
// Body shape (JSON):
//   { email: "person@example.com" }
//
// Response:
//   { exists: true | false }
//   { exists: true, soft: true }   // transient server error → permissive
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

function jsonResp(headers: Record<string, string>, body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...headers, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req: Request): Promise<Response> => {
  const CORS_HEADERS = corsHeaders(req);
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS_HEADERS });
  if (req.method !== 'POST') return jsonResp(CORS_HEADERS, { error: 'Method not allowed' }, 405);

  // Require a real Bearer token. We won't even tell anonymous
  // callers whether an email is taken — that would be a free
  // user-enumeration endpoint.
  const authHeader = req.headers.get('Authorization') ?? req.headers.get('authorization');
  if (!authHeader?.startsWith('Bearer ')) return jsonResp(CORS_HEADERS, { error: 'Unauthorized' }, 401);
  const accessToken = authHeader.slice('Bearer '.length).trim();
  if (!accessToken) return jsonResp(CORS_HEADERS, { error: 'Unauthorized' }, 401);

  const verifyClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
  const { data: userData, error: userErr } = await verifyClient.auth.getUser(accessToken);
  if (userErr || !userData?.user?.id) {
    return jsonResp(CORS_HEADERS, { error: 'Unauthorized' }, 401);
  }

  // Authorisation: only owners (i.e. users who actually have a
  // business to invite people INTO) can call this endpoint. This
  // throttles drive-by enumeration — a freshly signed-up account
  // with no businesses can't probe whether arbitrary emails are
  // registered. Owners are the natural caller anyway (Team page
  // is owner-only in the UI), so legitimate use isn't affected.
  // Uses the user's own JWT for the check so RLS applies; no
  // service-role escalation needed for this gate.
  try {
    const userJwtClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: `Bearer ${accessToken}` } },
    });
    const { count, error: countErr } = await userJwtClient
      .from('app_businesses')
      .select('id', { count: 'exact', head: true })
      .eq('owner_id', userData.user.id)
      .limit(1);
    if (countErr) {
      // RLS or schema issue — block defensively. Better to fail
      // closed than to leak.
      return jsonResp(CORS_HEADERS, { error: 'Unauthorized' }, 403);
    }
    if (!count || count < 1) {
      return jsonResp(CORS_HEADERS, { error: 'Not allowed: no businesses' }, 403);
    }
  } catch (_) {
    return jsonResp(CORS_HEADERS, { error: 'Unauthorized' }, 403);
  }

  // Parse body.
  let body: any = {};
  try { body = await req.json(); } catch (_) { return jsonResp(CORS_HEADERS, { error: 'Invalid JSON' }, 400); }
  const rawEmail = String(body?.email ?? '').trim().toLowerCase();
  // Tight email shape check — full RFC validation isn't needed, we
  // just want to reject obvious garbage before hitting the admin API.
  if (!rawEmail || rawEmail.length > 320 || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(rawEmail)) {
    return jsonResp(CORS_HEADERS, { error: 'Invalid email' }, 400);
  }

  const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // Page through admin.listUsers and look for an exact (lowercased)
  // email match. supabase-js v2 admin.listUsers takes
  // { page, perPage } and returns { data: { users, total? }, error }.
  // We cap at 50 pages of 1000 = 50k users — more than enough for
  // the realistic Hisabs user base. If you ever exceed that, switch
  // this function to a direct SQL query against auth.users via the
  // PostgREST endpoint (auth.users is normally not exposed via REST
  // but the service-role client can query it through a custom view
  // or RPC). For now, paging is simpler and works fine at small scale.
  try {
    const perPage = 1000;
    for (let page = 1; page <= 50; page++) {
      const { data, error } = await adminClient.auth.admin.listUsers({ page, perPage });
      if (error) {
        // Transient backend issue — be permissive so a flaky network
        // doesn't block legitimate invites.
        return jsonResp(CORS_HEADERS, { exists: true, soft: true });
      }
      const users = data?.users || [];
      for (const u of users) {
        if (String(u.email || '').toLowerCase() === rawEmail) {
          return jsonResp(CORS_HEADERS, { exists: true });
        }
      }
      // listUsers returns fewer than perPage on the last page.
      if (users.length < perPage) break;
    }
    return jsonResp(CORS_HEADERS, { exists: false });
  } catch (_) {
    return jsonResp(CORS_HEADERS, { exists: true, soft: true });
  }
});
