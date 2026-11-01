// اختبار صفحة متابعة الأهل ولوحة الإدارة بمتصفح حقيقي، مع سيرفر وهمي.
// التشغيل: node site/test/pages.test.mjs  (بدها playwright + chromium)
import { chromium } from 'playwright';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
const server = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://x');
  if (url.pathname === '/config.js') {
    res.setHeader('content-type', 'text/javascript');
    return res.end('window.MISHWAR = { url: "https://demo.supabase.co", anon: "anon-key" };');
  }
  let file = path.join(root, decodeURIComponent(url.pathname));
  if (fs.existsSync(file) && fs.statSync(file).isDirectory()) file = path.join(file, 'index.html');
  if (!file.startsWith(root) || !fs.existsSync(file)) { res.statusCode = 404; return res.end('nf'); }
  res.setHeader('content-type', file.endsWith('.html') ? 'text/html; charset=utf-8' : file.endsWith('.css') ? 'text/css' : 'text/javascript');
  fs.createReadStream(file).pipe(res);
}).listen(0);
const base = `http://127.0.0.1:${server.address().port}`;
const token = 'a'.repeat(36);
let fails = 0;
const check = (ok, msg) => { console.log(`${ok ? '✓' : '✗'} ${msg}`); if (!ok) fails++; };

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
const errors = [];
page.on('pageerror', (e) => errors.push(e.message));
await page.route(/tile\.openstreetmap|fonts\.(googleapis|gstatic)/, (r) => r.abort());

// 1) رابط صالح مع موقع
let calls = 0;
await page.route('https://demo.supabase.co/rest/v1/rpc/get_shared_trip', async (r) => {
  calls++;
  const body = JSON.parse(r.request().postData());
  if (body.p_token !== token) return r.fulfill({ json: null });
  const now = Date.now();
  await r.fulfill({ json: {
    from: 'اللاذقية', to: 'دمشق', from_city: 'latakia', to_city: 'damascus',
    departure_at: new Date(now - 3600e3).toISOString(), arrival_at: new Date(now + 3 * 3600e3).toISOString(), status: 'in_progress',
    rider: '<img src=x onerror=alert(1)>', driver: 'سامر', car: 'كيا ريو · فضي', plate: 'LAT 123456',
    location: { lat: 34.9, lon: 35.9, accuracy: 10, updated_at: new Date(now - 20e3).toISOString() },
  } });
});
await page.goto(`${base}/track/?t=${token}`);
await page.waitForSelector('#sheet:not([hidden])', { timeout: 5000 });
check((await page.textContent('#from')) === 'اللاذقية', 'بيعرض مدينة الانطلاق');
check((await page.textContent('#plate')) === 'LAT 123456', 'بيعرض رقم السيارة');
check((await page.textContent('#liveText')) === 'مباشر', 'الموقع الحديث بيتعلّم مباشر');
check((await page.$$('#title img')).length === 0 && (await page.textContent('#title')).includes('<img'), 'الأسماء بتنعرض كنص (ما في XSS)');
check((await page.$$('.pin')).length === 1, 'علامة الموقع عالخريطة');
check(calls === 1, 'طلب واحد للسيرفر');
await page.screenshot({ path: '/tmp/track.png' });

// 2) رابط مو صالح
await page.goto(`${base}/track/?t=${'b'.repeat(36)}`);
await page.waitForSelector('#invalid.on', { timeout: 5000 });
check(true, 'رابط منتهي بيعرض رسالة واضحة');
await page.goto(`${base}/track/?t=../../etc`);
check(await page.isVisible('#invalid.on'), 'رمز بصيغة غلط ما بيوصل للسيرفر');

// 3) لوحة الإدارة: شاشة الدخول
await page.route('https://demo.supabase.co/auth/v1/**', (r) => r.fulfill({ status: 400, json: { error: 'invalid_grant', error_description: 'Invalid login credentials' } }));
await page.goto(`${base}/admin/`);
await page.waitForSelector('form.login', { timeout: 5000 });
await page.fill('#email', 'x@y.z');
await page.fill('#pass', 'wrong');
await page.click('button[type=submit]');
await page.waitForFunction(() => document.getElementById('toast').textContent.includes('غلط'), null, { timeout: 5000 });
check(true, 'دخول غلط بلوحة الإدارة بيعطي رسالة');
await page.screenshot({ path: '/tmp/admin.png' });

// 4) لوحة الإدارة: نقاط التجمع على الخريطة (جلسة مدير وهمية)
const ctx2 = await browser.newContext({ viewport: { width: 1280, height: 900 } });
const p2 = await ctx2.newPage();
p2.on('pageerror', (e) => errors.push(e.message));
await p2.route(/tile\.openstreetmap|fonts\.(googleapis|gstatic)/, (r) => r.abort());
const exp = Math.floor(Date.now() / 1000) + 3600;
const jwt = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
const access = `${jwt({ alg: 'HS256', typ: 'JWT' })}.${jwt({ sub: '00000000-0000-0000-0000-00000000000a', role: 'authenticated', exp })}.sig`;
await p2.addInitScript(([tok, e]) => {
  localStorage.setItem('sb-demo-auth-token', JSON.stringify({ access_token: tok, refresh_token: 'r', token_type: 'bearer', expires_in: 3600, expires_at: e,
    user: { id: '00000000-0000-0000-0000-00000000000a', aud: 'authenticated', role: 'authenticated', email: 'a@m.test' } }));
}, [access, exp]);
const places = [];
let upsert = null;
let reviewed = null;
await p2.route('https://demo.supabase.co/**', async (r) => {
  const u = new URL(r.request().url());
  const send = (json, headers = {}) => r.fulfill({ status: 200, contentType: 'application/json', headers: { 'content-range': '0-0/0', ...headers }, body: JSON.stringify(json) });
  if (u.pathname.endsWith('/rpc/my_profile')) return send({ id: '00000000-0000-0000-0000-00000000000a', role: 'admin', full_name: 'مدير' });
  if (u.pathname.endsWith('/rpc/admin_stats')) return send({ users: 1, drivers: 0, pending_applications: 0, trips_upcoming: 0, trips_today: 0, bookings_week: 0, confirmed_week: 0, open_reports: 0, suspended: 0, top_routes: [] });
  if (u.pathname.endsWith('/rpc/admin_upsert_place')) {
    upsert = JSON.parse(r.request().postData());
    places.push({ id: 'p1', city_id: upsert.p_city, name_ar: upsert.p_name_ar, name_en: upsert.p_name_en, name_de: upsert.p_name_de, kind: upsert.p_kind, lat: upsert.p_lat, lon: upsert.p_lon, active: true });
    return send('p1');
  }
  if (u.pathname.endsWith('/rest/v1/places')) return send(places);
  if (u.pathname.endsWith('/rpc/admin_wallet_stats')) return send({ commission_month: 120000, topups_month: 900000, balances_total: 780000, drivers_low: 2, pending_topups: 1, agents: [{ label: 'مكتب كراج حمص', city: 'homs', active: true, month_total: 300000 }] });
  if (u.pathname.endsWith('/rest/v1/topup_requests')) return send(reviewed ? [] : [{ id: 'q1', amount_syp: 250000, method: 'sham_cash', reference: '<img src=x>SC-1', created_at: new Date().toISOString(), driver: { full_name: 'سامر' } }]);
  if (u.pathname.endsWith('/rest/v1/app_settings')) return send([{ key: 'commission_pct', value: 8 }, { key: 'commission_min_syp', value: 2000 }, { key: 'credit_limit_syp', value: 0 }, { key: 'payment_accounts', value: { sham_cash: '0999' } }]);
  if (u.pathname.endsWith('/rpc/admin_review_topup')) { reviewed = JSON.parse(r.request().postData()); return send(null); }
  return send([]);
});
await p2.goto(`${base}/admin/`);
await p2.waitForSelector('nav [role=tab]', { timeout: 5000 });
await p2.click('nav [role=tab]:has-text("نقاط التجمع")');
await p2.waitForSelector('.leaflet-container', { timeout: 5000 });
check(await p2.isVisible('text=لسا ما في نقاط'), 'قائمة النقاط فاضية بالبداية');
await p2.selectOption('#pcity', 'homs');
await p2.fill('#pname', 'كراج <b>حمص</b> الجديد');
await p2.fill('#pen', 'Homs New Garage');
const box = await p2.locator('.leaflet-container').boundingBox();
await p2.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
check((await p2.inputValue('#plat')) !== '' && (await p2.$$('.pin')).length === 1, 'الضغط على الخريطة بيحط دبوس وبيعبّي الإحداثيات');
await p2.click('form.card button[type=submit]');
await p2.waitForFunction(() => document.getElementById('toast').textContent.includes('انحفظت'), null, { timeout: 5000 });
check(upsert && upsert.p_city === 'homs' && upsert.p_name_en === 'Homs New Garage' && typeof upsert.p_lat === 'number', 'الحفظ بيبعت المدينة والأسماء والإحداثيات');
await p2.waitForSelector('text=كراج <b>حمص</b> الجديد', { timeout: 5000 });
check((await p2.$$('.list b')).length === 0, 'اسم النقطة بينعرض كنص (ما في XSS)');
check((await p2.$$('path.leaflet-interactive')).length === 1, 'النقطة ظهرت على الخريطة');
await p2.screenshot({ path: '/tmp/admin_places.png' });

await p2.click('nav [role=tab]:has-text("المحفظة")');
await p2.waitForSelector('text=عمولات الشهر', { timeout: 5000 });
check(await p2.isVisible('text=120,000 ل.س'), 'إيرادات العمولة ظاهرة');
check((await p2.inputValue('#spct')) === '8' && (await p2.inputValue('#acc_sham')) === '0999', 'الإعدادات انقرت');
check((await p2.$$('.item img')).length === 0, 'رقم العملية بينعرض كنص (ما في XSS)');
await p2.click('button:has-text("تأكدت، اشحن")');
await p2.waitForFunction(() => document.getElementById('toast').textContent.includes('انشحن'), null, { timeout: 5000 });
check(reviewed && reviewed.p_request === 'q1' && reviewed.p_approve === true, 'الموافقة على الشحن انبعتت');
await p2.screenshot({ path: '/tmp/admin_wallet.png', fullPage: true });
await ctx2.close();

check(errors.length === 0, `ما في أخطاء JavaScript ${errors.join(' | ')}`);
await browser.close();
server.close();
process.exit(fails ? 1 : 0);
