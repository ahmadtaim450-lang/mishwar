// حذف حساب نهائياً (للمدير بس): بيحذف أوراق السائق من التخزين، وبعدين المستخدم من Auth
// (وكل بياناتو بتنحذف معو بالـ cascade). بيتسجّل بسجل العمليات.
import { createClient } from 'npm:@supabase/supabase-js@2';
import { cors, json } from '../_shared/cors.ts';

Deno.serve(async (req) => {
  const headers = cors(req);
  if (req.method === 'OPTIONS') return new Response('ok', { headers });
  if (req.method !== 'POST') return json({ error: 'method' }, 405, headers);

  const url = Deno.env.get('SUPABASE_URL')!;
  const auth = req.headers.get('Authorization') ?? '';
  if (!auth.startsWith('Bearer ')) return json({ error: 'unauthorized' }, 401, headers);

  // مين عم يطلب؟ منتأكد من الدور من السيرفر نفسو
  const caller = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, { global: { headers: { Authorization: auth } }, auth: { persistSession: false } });
  const { data: me } = await caller.rpc('my_profile');
  if (!me || me.role !== 'admin') return json({ error: 'forbidden' }, 403, headers);

  let userId: string;
  let force = false;
  try {
    const body = await req.json();
    userId = String(body.user_id);
    force = body.force === true;
    if (!/^[0-9a-f-]{36}$/.test(userId)) throw new Error();
  } catch {
    return json({ error: 'bad_request' }, 400, headers);
  }
  if (userId === me.id) return json({ error: 'cannot_delete_self' }, 400, headers);

  const admin = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, { auth: { persistSession: false } });
  const { data: target } = await admin.from('profiles').select('id, deletion_requested_at').eq('id', userId).maybeSingle();
  if (!target) return json({ error: 'not_found' }, 404, headers);
  if (!target.deletion_requested_at && !force) return json({ error: 'not_requested' }, 409, headers);

  // الأوراق والصور
  for (const bucket of ['driver-docs', 'avatars']) {
    const { data: dirs } = await admin.storage.from(bucket).list(userId, { limit: 1000 });
    const paths: string[] = [];
    for (const d of dirs ?? []) {
      if (d.id) paths.push(`${userId}/${d.name}`);
      else {
        const { data: files } = await admin.storage.from(bucket).list(`${userId}/${d.name}`, { limit: 1000 });
        for (const f of files ?? []) paths.push(`${userId}/${d.name}/${f.name}`);
      }
    }
    if (paths.length) await admin.storage.from(bucket).remove(paths);
  }

  const { error } = await admin.auth.admin.deleteUser(userId);
  if (error) return json({ error: 'delete_failed' }, 500, headers);
  await admin.from('audit_log').insert({ actor_id: me.id, action: 'account.deleted', entity: 'profile', entity_id: userId, meta: { force } });
  return json({ deleted: true }, 200, headers);
});
