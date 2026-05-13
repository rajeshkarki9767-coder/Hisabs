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

// CORS: allow the Hisabs deployment origin to call this. The wildcard
// is fine here because the function authenticates via JWT — origin alone
// can't escalate.
const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

Deno.serve(async (req: Request): Promise<Response> => {
  // Preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS_HEADERS });
  }
  if (req.method !== 'POST') {
    return json({ error: 'Method not allowed' }, 405);
  }

  // 1. Extract the caller's JWT from the Authorization header.
  const authHeader = req.headers.get('Authorization') ?? req.headers.get('authorization');
  if (!authHeader?.startsWith('Bearer ')) {
    return json({ error: 'Missing Authorization Bearer token' }, 401);
  }
  const accessToken = authHeader.slice('Bearer '.length).trim();
  if (!accessToken) {
    return json({ error: 'Empty Authorization token' }, 401);
  }

  // 2. Verify the JWT. Use the ANON client (no admin powers); supabase-js
  //    will validate the token against the Supabase Auth public key.
  const verifyClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
  const { data: userData, error: userErr } = await verifyClient.auth.getUser(accessToken);
  if (userErr || !userData?.user?.id) {
    return json({ error: 'Invalid or expired session', detail: userErr?.message ?? null }, 401);
  }
  const userId = userData.user.id;
  const userEmail = userData.user.email ?? null;

  // 3. Delete the auth user using the service_role client. This call
  //    bypasses RLS because service_role is the database superuser
  //    role — it can do anything. We constrain to "the caller's own
  //    user_id" so the bypass can't be abused.
  if (!SUPABASE_SERVICE_ROLE) {
    return json({ error: 'Server misconfigured: missing service role' }, 500);
  }
  const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // Before deleting the auth user, the Hisabs client should already have
  // hard-deleted the user's app data via normal cascades. We don't repeat
  // that work here — the RLS policies wouldn't let this function's caller
  // see other users' data anyway, but we'd need to use the service_role
  // for the cascade, which is more dangerous than we need.

  const { error: delErr } = await adminClient.auth.admin.deleteUser(userId);
  if (delErr) {
    return json({ error: 'Failed to delete user', detail: delErr.message }, 500);
  }

  return json({ ok: true, deleted_user_id: userId, deleted_email: userEmail });
});

function json(body: any, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
  });
}
