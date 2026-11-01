// بيبعت إشعار FCM لكل أجهزة المستخدم. بيناديه تريغر قاعدة البيانات (pg_net) مع كل إشعار جديد.
// الأسرار: PUSH_SECRET (نفس قيمة push_secret بالـ Vault)، FCM_SERVICE_ACCOUNT (JSON حساب الخدمة من Firebase)
import { createClient } from 'npm:@supabase/supabase-js@2';
import { importPKCS8, SignJWT } from 'npm:jose@5';
import { json } from '../_shared/cors.ts';

type ServiceAccount = { project_id: string; client_email: string; private_key: string };
let cached: { token: string; exp: number } | null = null;

async function googleToken(sa: ServiceAccount): Promise<string> {
  if (cached && cached.exp > Date.now() + 60_000) return cached.token;
  const key = await importPKCS8(sa.private_key, 'RS256');
  const now = Math.floor(Date.now() / 1000);
  const assertion = await new SignJWT({ scope: 'https://www.googleapis.com/auth/firebase.messaging' })
    .setProtectedHeader({ alg: 'RS256', typ: 'JWT' })
    .setIssuer(sa.client_email).setAudience('https://oauth2.googleapis.com/token')
    .setIssuedAt(now).setExpirationTime(now + 3600).sign(key);
  const r = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion }),
  });
  if (!r.ok) throw new Error(`oauth ${r.status}`);
  const j = await r.json();
  cached = { token: j.access_token, exp: Date.now() + j.expires_in * 1000 };
  return cached.token;
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'method' }, 405);
  const secret = Deno.env.get('PUSH_SECRET');
  if (!secret || req.headers.get('x-push-secret') !== secret) return json({ error: 'unauthorized' }, 401);

  let id: number;
  try {
    id = Number((await req.json()).notification_id);
    if (!Number.isInteger(id) || id <= 0) throw new Error();
  } catch {
    return json({ error: 'bad_request' }, 400);
  }

  const sb = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, { auth: { persistSession: false } });
  const { data: n, error } = await sb.from('notifications').select('id, user_id, kind, title, body, data').eq('id', id).maybeSingle();
  if (error || !n) return json({ error: 'not_found' }, 404);
  const { data: devices } = await sb.from('device_tokens').select('token, platform').eq('user_id', n.user_id);
  if (!devices?.length) return json({ sent: 0 });

  const raw = Deno.env.get('FCM_SERVICE_ACCOUNT');
  if (!raw) return json({ sent: 0, skipped: 'FCM_SERVICE_ACCOUNT not set' });
  const sa = JSON.parse(raw) as ServiceAccount;
  const access = await googleToken(sa);

  // بيانات الإشعار لازم تكون نصوص بـ FCM
  const data: Record<string, string> = { kind: n.kind, notification_id: String(n.id) };
  for (const [k, v] of Object.entries(n.data ?? {})) data[k] = String(v);

  let sent = 0;
  for (const d of devices) {
    const r = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${access}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ message: {
        token: d.token,
        notification: { title: n.title, body: n.body },
        data,
        android: { priority: 'HIGH', notification: { channel_id: 'mishwar', sound: 'default' } },
        apns: { payload: { aps: { sound: 'default' } } },
      } }),
    });
    if (r.ok) sent++;
    // التوكن انتهى أو الجهاز شال التطبيق: منحذفو
    else if (r.status === 404 || r.status === 400) await sb.from('device_tokens').delete().eq('token', d.token);
  }
  return json({ sent });
});
