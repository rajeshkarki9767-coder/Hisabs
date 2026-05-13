// ============================================================
// Hisabs Edge Function: delete-self-account
// ============================================================
// Purpose: A user who has clicked "Delete all my data and sign out" in
// Hisabs has had their app data deleted (businesses, members, profile).
// What remains is their auth.users entry — email + hashed password.
// This function removes that final piece, so the email can be re-used
// for a fresh sign-up later if the user changes their mind.
//
// Why an Edge Function and not a client-side call: deleting an auth
// user requires the service_role key, which has admin access to the
// whole database. Embedding it in the client would let any user delete
// anyone — catastrophic. The service_role key lives only as an env var
// on the server, never sent over the wire.
//
// Security model:
//   1. Caller must present a valid Authorization: Bearer <JWT> header
//   2. We verify the JWT using the anon key client (NOT service_role)
//   3. We confirm a user is returned and extract their UUID
//   4. We delete THAT user — never a UUID from the request body
//
// This means a caller can only ever delete themselves. There is no
// admin endpoint, no "delete by id" parameter, no way to escalate.
// ============================================================

// deno-lint-ignore-file no-explicit-any
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';

// Vercel/Cloudflare/Deno-style globals that Supabase Edge Functions provide.
declare const Deno: { env: { get(k: string): string | undefined }; serve: (h: (r: Request) => Response | Promise<Response>) => void };

const SUPABASE_URL          = Deno.env.get('SUPABASE_URL')          ?? '';
const SUPABASE_ANON_KEY     = Deno.env.get('SUPABASE_ANON_KEY')     ?? '';
const SUPABASE_SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

// CORS allowlist. Even though we authenticate via JWT (so origin alone
// can't escalate), restricting Allow-Origin is defense-in-depth — it
// stops a third-party site from being able to invoke this function from
// a browser even with social-engineering. The function still works
// server-to-server because CORS only applies to browser fetches.
//
// To support preview deploys, list each one here. Edit this list and
// redeploy when adding new domains.
const ALLOWED_ORIGINS = new Set([
  'https://hisabs.vercel.app',
  // Add additional Hisabs domains here if you have them, e.g.:
  // 'https://hisabs-staging.vercel.app',
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
  // Preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS_HEADERS });
  }
  if (req.method !== 'POST') {
    return jsonResp(CORS_HEADERS, { error: 'Method not allowed' }, 405);
  }

  // 1. Extract the caller's JWT from the Authorization header.
  const authHeader = req.headers.get('Authorization') ?? req.headers.get('authorization');
  if (!authHeader?.startsWith('Bearer ')) {
    return jsonResp(CORS_HEADERS, { error: 'Unauthorized' }, 401);
  }
  const accessToken = authHeader.slice('Bearer '.length).trim();
  if (!accessToken) {
    return jsonResp(CORS_HEADERS, { error: 'Unauthorized' }, 401);
  }

  // 2. Verify the JWT. Use the ANON client (no admin powers); supabase-js
  //    will validate the token against the Supabase Auth public key.
  const verifyClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
  const { data: userData, error: userErr } = await verifyClient.auth.getUser(accessToken);
  if (userErr || !userData?.user?.id) {
    // Don't leak whether token was missing/expired/forged.
    return jsonResp(CORS_HEADERS, { error: 'Unauthorized' }, 401);
  }
  const userId = userData.user.id;
  const userEmail = userData.user.email ?? null;

  // 3. Delete the auth user using the service_role client.
  if (!SUPABASE_SERVICE_ROLE) {
    console.error('Server misconfigured: missing SUPABASE_SERVICE_ROLE_KEY');
    return jsonResp(CORS_HEADERS, { error: 'Server error' }, 500);
  }
  const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const { error: delErr } = await adminClient.auth.admin.deleteUser(userId);
  if (delErr) {
    // Log details internally; return generic error to caller.
    console.error('Failed to delete user', userId, delErr);
    return jsonResp(CORS_HEADERS, { error: 'Delete failed' }, 500);
  }

  return jsonResp(CORS_HEADERS, { ok: true, deleted_user_id: userId, deleted_email: userEmail });
});

function jsonResp(corsHdrs: Record<string, string>, body: any, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHdrs, 'Content-Type': 'application/json' },
  });
}
