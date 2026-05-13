// ============================================================
// Hisabs Edge Function: list-my-sessions
// ============================================================
// Returns the list of active sessions for the calling user, enriched
// with:
//   - city / country, looked up from the session's IP via ipapi.co
//     (free tier, no API key, ~1000 lookups/day per IP origin)
//   - custom device names from app_device_names (joined by session_id
//     and falling back to most-recent name for the same browser)
//
// Each lookup is cached in memory across the function's lifetime to
// avoid burning the ipapi.co quota when the same IP appears multiple
// times. The cache is per-invocation-process; cold starts re-fetch.
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
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Vary': 'Origin',
  };
}

// Simple in-memory cache for IP → location lookups. Bound by entry
// count so a runaway loop can't blow up function memory. ipapi.co
// rarely changes geo for a given IP within hours, so a 1-hour TTL
// is fine.
const GEO_CACHE = new Map<string, { city: string; country: string; cachedAt: number }>();
const GEO_TTL_MS = 60 * 60 * 1000;
const GEO_CACHE_MAX = 200;

async function lookupGeo(ip: string): Promise<{ city: string; country: string }> {
  if (!ip || ip === '127.0.0.1' || ip.startsWith('192.168.') || ip.startsWith('10.') || ip === '::1') {
    return { city: '', country: '' };
  }
  const cached = GEO_CACHE.get(ip);
  if (cached && Date.now() - cached.cachedAt < GEO_TTL_MS) {
    return { city: cached.city, country: cached.country };
  }
  try {
    // ipapi.co's free endpoint. No key required. Strict 4s timeout so
    // a slow third-party can't stall the whole sessions list response.
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), 4000);
    const resp = await fetch(`https://ipapi.co/${encodeURIComponent(ip)}/json/`, { signal: ctrl.signal });
    clearTimeout(t);
    if (!resp.ok) {
      // 429 = rate limited; 404 = unknown IP. Either way, return blank
      // and cache the blank so we don't retry for an hour.
      GEO_CACHE.set(ip, { city: '', country: '', cachedAt: Date.now() });
      return { city: '', country: '' };
    }
    const j: any = await resp.json();
    const entry = { city: String(j.city || ''), country: String(j.country_name || j.country || ''), cachedAt: Date.now() };
    if (GEO_CACHE.size >= GEO_CACHE_MAX) {
      // Evict oldest. Map insertion order is preserved.
      const firstKey = GEO_CACHE.keys().next().value;
      if (firstKey) GEO_CACHE.delete(firstKey);
    }
    GEO_CACHE.set(ip, entry);
    return { city: entry.city, country: entry.country };
  } catch (_) {
    return { city: '', country: '' };
  }
}

Deno.serve(async (req: Request): Promise<Response> => {
  const CORS_HEADERS = corsHeaders(req);
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS_HEADERS });
  if (req.method !== 'GET' && req.method !== 'POST') return jsonResp(CORS_HEADERS, { error: 'Method not allowed' }, 405);

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
    console.error('Server misconfigured: missing SUPABASE_SERVICE_ROLE_KEY');
    return jsonResp(CORS_HEADERS, { error: 'Server error' }, 500);
  }
  const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // Fetch all sessions for this user.
  const { data: sessRows, error: sessErr } = await adminClient
    .schema('auth')
    .from('sessions')
    .select('id, created_at, updated_at, user_agent, ip, not_after')
    .eq('user_id', userId)
    .order('updated_at', { ascending: false });
  if (sessErr) {
    console.error('list-my-sessions: read sessions failed', sessErr);
    return jsonResp(CORS_HEADERS, { error: 'Could not read sessions' }, 500);
  }

  // Drop expired.
  const now = Date.now();
  const live = (sessRows || []).filter((r: any) => !r.not_after || new Date(r.not_after).getTime() > now);

  // Fetch device names for this user. Keyed by session_id; we also keep
  // a fallback by most-recent device_id for sessions that were created
  // after the most recent name update.
  const { data: nameRows } = await adminClient
    .from('app_device_names')
    .select('device_id, name, session_id, updated_at')
    .eq('user_id', userId);
  const nameBySession = new Map<string, string>();
  for (const r of (nameRows || [])) {
    if (r.session_id && r.name) nameBySession.set(r.session_id, r.name);
  }

  // Enrich each session with geo + name. We cap concurrency so a user
  // with many stale sessions doesn't burst 20 parallel ipapi.co calls
  // and trigger their per-IP rate limit. The cache makes repeats free.
  async function mapWithLimit<T, R>(items: T[], limit: number, fn: (t: T) => Promise<R>): Promise<R[]> {
    const out: R[] = new Array(items.length);
    let idx = 0;
    const workers = Array.from({ length: Math.min(limit, items.length) }, async () => {
      while (true) {
        const i = idx++;
        if (i >= items.length) return;
        out[i] = await fn(items[i]);
      }
    });
    await Promise.all(workers);
    return out;
  }
  const enriched = await mapWithLimit(live, 3, async (s: any) => {
    const geo = s.ip ? await lookupGeo(s.ip) : { city: '', country: '' };
    return {
      id: s.id,
      created_at: s.created_at,
      updated_at: s.updated_at,
      user_agent: s.user_agent,
      ip: s.ip,
      not_after: s.not_after,
      city: geo.city,
      country: geo.country,
      device_name: nameBySession.get(s.id) || null,
    };
  });

  return jsonResp(CORS_HEADERS, { sessions: enriched });
});

function jsonResp(corsHdrs: Record<string, string>, body: any, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHdrs, 'Content-Type': 'application/json' },
  });
}
