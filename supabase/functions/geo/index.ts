// خدمة الخرائط للتطبيق: بحث أماكن، عنوان من إحداثيات، ومسارات بديلة.
// المفاتيح بتضل هون بالسيرفر، والنتائج بتنحفظ بكاش، وفي حد طلبات لكل مستخدم بالساعة
// لحتى ما تطلع تكاليف أو حظر من المزود.
import { createClient } from 'npm:@supabase/supabase-js@2';
import { cors, json } from '../_shared/cors.ts';
import { pickProvider, ProviderError } from './providers.ts';
import { cacheKey, parseRequest, ttlHours } from './request.ts';

const provider = pickProvider((k) => Deno.env.get(k));
const hourlyLimit = Number(Deno.env.get('GEO_HOURLY_LIMIT') ?? '100');

Deno.serve(async (req) => {
  const headers = cors(req);
  if (req.method === 'OPTIONS') return new Response('ok', { headers });
  if (req.method !== 'POST') return json({ error: 'method' }, 405, headers);

  const url = Deno.env.get('SUPABASE_URL')!;
  const auth = req.headers.get('Authorization') ?? '';
  if (!auth.startsWith('Bearer ')) return json({ error: 'unauthorized' }, 401, headers);
  const caller = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, { global: { headers: { Authorization: auth } }, auth: { persistSession: false } });
  const { data: who } = await caller.auth.getUser(auth.slice(7));
  if (!who?.user) return json({ error: 'unauthorized' }, 401, headers);

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return json({ error: 'bad_request' }, 400, headers);
  }
  const r = parseRequest(body);
  if (typeof r === 'string') return json({ error: r }, 400, headers);

  const admin = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, { auth: { persistSession: false } });
  const key = cacheKey(provider.id, r);
  const since = new Date(Date.now() - ttlHours(r) * 3600e3).toISOString();
  const { data: hit } = await admin.from('geo_cache').select('body').eq('key', key).gte('created_at', since).maybeSingle();
  if (hit) return json({ ...hit.body, cached: true }, 200, headers);

  // الحد بينحسب على الطلبات اللي بتروح للمزود بس
  const { data: allowed, error: limErr } = await admin.rpc('geo_take', { p_user: who.user.id, p_limit: hourlyLimit });
  if (limErr) return json({ error: 'internal' }, 500, headers);
  if (!allowed) return json({ error: 'rate_limited' }, 429, headers);

  let out: Record<string, unknown>;
  try {
    switch (r.op) {
      case 'autocomplete': out = { results: await provider.autocomplete(r.q, r.lang, r.near) }; break;
      case 'geocode': out = { results: await provider.geocode(r.q, r.lang) }; break;
      case 'reverse': out = { result: await provider.reverse(r.at, r.lang) }; break;
      case 'route': out = { routes: (await provider.route(r.points, r.alternatives)).slice(0, 3) }; break;
    }
  } catch (e) {
    console.error('geo provider', provider.id, r.op, e instanceof Error ? e.message : e);
    const status = e instanceof ProviderError && e.status === 429 ? 503 : 502;
    return json({ error: 'provider_unavailable' }, status, headers);
  }
  out.provider = provider.id;
  await admin.from('geo_cache').upsert({ key, body: out, created_at: new Date().toISOString() });
  return json({ ...out, cached: false }, 200, headers);
});
