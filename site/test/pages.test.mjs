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

check(errors.length === 0, `ما في أخطاء JavaScript ${errors.join(' | ')}`);
await browser.close();
server.close();
process.exit(fails ? 1 : 0);
