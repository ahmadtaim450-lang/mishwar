// اختبارات دالة الخرائط بلا شبكة: تحويل ردود المزودات (بنفس شكل ردودهم الحقيقية)،
// والتحقق من الطلبات، ومفاتيح الكاش.  التشغيل: deno test supabase/functions/geo
import { fakeProvider, orsProvider, osmProvider, parseNominatim, parseOrsRoute, parseOsrm, parsePelias, parsePhoton, pickProvider, ProviderError } from './providers.ts';
import { cacheKey, parseRequest } from './request.ts';

function eq(a: unknown, b: unknown, msg = '') {
  if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${msg}\n  expected ${JSON.stringify(b)}\n  got      ${JSON.stringify(a)}`);
}
function ok(c: unknown, msg: string) {
  if (!c) throw new Error(msg);
}

// ── ردود بشكل المزودات ──
const peliasFx = {
  type: 'FeatureCollection',
  features: [
    { type: 'Feature', geometry: { type: 'Point', coordinates: [36.7137, 34.7324] }, properties: { name: 'حمص', label: 'حمص, سوريا', layer: 'locality' } },
    { type: 'Feature', geometry: { type: 'Point', coordinates: ['bad', 1] }, properties: { name: 'خربان' } },
  ],
};
const photonFx = {
  type: 'FeatureCollection',
  features: [
    { type: 'Feature', geometry: { type: 'Point', coordinates: [36.2765, 33.5138] }, properties: { name: 'دمشق', city: 'دمشق', state: 'محافظة دمشق', countrycode: 'SY', osm_value: 'city' } },
    { type: 'Feature', geometry: { type: 'Point', coordinates: [35.5, 33.89] }, properties: { name: 'Beirut', countrycode: 'LB', osm_value: 'city' } },
  ],
};
const nominatimFx = {
  place_id: 1, lat: '35.5196', lon: '35.7832', display_name: 'شارع بغداد, اللاذقية, سوريا', name: '', type: 'residential', category: 'highway',
  address: { road: 'شارع بغداد', suburb: 'الزراعة', city: 'اللاذقية', state: 'محافظة اللاذقية', country: 'سوريا' },
};
const orsFx = {
  type: 'FeatureCollection',
  features: [
    { type: 'Feature', properties: { summary: { distance: 182345.6, duration: 8123.4 } }, geometry: { type: 'LineString', coordinates: [[35.78, 35.52], [36.0, 35.2], [36.71, 34.73]] } },
    { type: 'Feature', properties: { summary: { distance: 201000, duration: 9300 } }, geometry: { type: 'LineString', coordinates: [[35.78, 35.52], [36.71, 34.73]] } },
  ],
};
const osrmFx = {
  code: 'Ok',
  routes: [{ distance: 160123.4, duration: 7000.6, legs: [{ summary: 'M1, M5' }], geometry: { type: 'LineString', coordinates: [[35.783205, 35.519612], [36.713712, 34.732411]] } }],
};

Deno.test('Pelias (ORS) → أماكن', () => {
  const r = parsePelias(peliasFx, 'ors');
  eq(r.length, 1, 'invalid coordinates dropped');
  eq(r[0], { name: 'حمص', label: 'حمص, سوريا', lat: 34.7324, lon: 36.7137, kind: 'locality', source: 'ors' });
  eq(parsePelias({}, 'ors'), []);
});

Deno.test('Photon → أماكن بسوريا بس', () => {
  const r = parsePhoton(photonFx);
  eq(r.length, 1, 'non-SY result dropped');
  eq(r[0].label, 'دمشق، محافظة دمشق');
});

Deno.test('Nominatim reverse → عنوان', () => {
  const r = parseNominatim(nominatimFx)!;
  eq(r.name, 'شارع بغداد');
  eq(r.label, 'شارع بغداد، الزراعة، اللاذقية، محافظة اللاذقية');
  eq([r.lat, r.lon], [35.5196, 35.7832]);
  eq(parseNominatim({ error: 'Unable to geocode' }), null);
});

Deno.test('مسارات ORS: مسافة ووقت والخط بصيغة [lat, lon]', () => {
  const r = parseOrsRoute(orsFx);
  eq(r.length, 2);
  eq([r[0].distance_m, r[0].duration_s], [182346, 8123]);
  eq(r[0].geometry[0], [35.52, 35.78]);
});

Deno.test('مسارات OSRM', () => {
  const r = parseOsrm(osrmFx);
  eq([r[0].distance_m, r[0].duration_s, r[0].summary], [160123, 7001, 'M1, M5']);
  eq(r[0].geometry[1], [34.73241, 36.71371]);
  eq(parseOsrm({ code: 'NoRoute', routes: [] }), []);
  let threw = false;
  try { parseOsrm({ code: 'InvalidQuery' }); } catch (e) { threw = e instanceof ProviderError; }
  ok(threw, 'OSRM error code throws');
});

Deno.test('ORS: المفتاح بالترويسة والبدائل بين نقطتين بس', async () => {
  const seen: { url: string; init?: RequestInit }[] = [];
  const f = (url: string, init?: RequestInit) => {
    seen.push({ url, init });
    return Promise.resolve(new Response(JSON.stringify(orsFx), { status: 200 }));
  };
  const p = orsProvider('SECRET', f);
  await p.route([{ lat: 35.52, lon: 35.78 }, { lat: 34.73, lon: 36.71 }], true);
  const body = JSON.parse(String(seen[0].init!.body));
  eq((seen[0].init!.headers as Record<string, string>).Authorization, 'SECRET');
  ok(!seen[0].url.includes('SECRET'), 'key not in route URL');
  eq(body.coordinates[0], [35.78, 35.52], 'lon,lat order');
  ok(body.alternative_routes, 'alternatives requested');
  await p.route([{ lat: 35.52, lon: 35.78 }, { lat: 35.0, lon: 36.0 }, { lat: 34.73, lon: 36.71 }], true);
  ok(!JSON.parse(String(seen[1].init!.body)).alternative_routes, 'no alternatives with via points');
  await p.autocomplete('حمص', 'ar', { lat: 35, lon: 36 });
  ok(seen[2].url.includes('boundary.country=SY') && seen[2].url.includes('focus.point.lat=35'), 'autocomplete scoped to Syria with focus');
});

Deno.test('ORS: 404 = ما في طريق، 429 = حد المزود', async () => {
  const p404 = orsProvider('K', () => Promise.resolve(new Response('{}', { status: 404 })));
  eq(await p404.route([{ lat: 35, lon: 36 }, { lat: 34, lon: 37 }], false), []);
  const p429 = orsProvider('K', () => Promise.resolve(new Response('{}', { status: 429 })));
  let status = 0;
  try { await p429.geocode('حمص', 'ar'); } catch (e) { status = (e as ProviderError).status; }
  eq(status, 429);
});

Deno.test('OSM: User-Agent وبحث محصور بسوريا', async () => {
  const seen: { url: string; init?: RequestInit }[] = [];
  const p = osmProvider('ops@example.com', (url, init) => {
    seen.push({ url, init });
    return Promise.resolve(new Response(JSON.stringify(url.includes('photon') ? photonFx : url.includes('nominatim') ? nominatimFx : osrmFx)));
  });
  eq((await p.autocomplete('دمشق', 'ar')).length, 1);
  ok(seen[0].url.includes('lang=default') && seen[0].url.includes('bbox=35.5,32.2,42.5,37.4'), 'photon arabic → default + bbox');
  ok(String((seen[0].init!.headers as Record<string, string>)['User-Agent']).includes('ops@example.com'), 'UA with contact');
  eq((await p.reverse({ lat: 35.5, lon: 35.8 }, 'ar'))!.name, 'شارع بغداد');
  eq((await p.route([{ lat: 35.5, lon: 35.8 }, { lat: 34.7, lon: 36.7 }], true)).length, 1);
  ok(seen[2].url.includes('alternatives=true'), 'osrm alternatives');
});

Deno.test('اختيار المزود', () => {
  eq(pickProvider((k) => ({ ORS_API_KEY: 'x' } as Record<string, string>)[k]).id, 'ors');
  eq(pickProvider(() => undefined).id, 'osm');
  eq(pickProvider((k) => ({ GEO_PROVIDER: 'fake' } as Record<string, string>)[k]).id, 'fake');
  let threw = false;
  try { pickProvider((k) => ({ GEO_PROVIDER: 'ors' } as Record<string, string>)[k]); } catch { threw = true; }
  ok(threw, 'ors without key fails loudly');
});

Deno.test('التحقق من الطلبات', () => {
  eq(parseRequest(null), 'bad_request');
  eq(parseRequest({ op: 'x' }), 'bad_op');
  eq(parseRequest({ op: 'autocomplete', q: 'ح' }), 'bad_query');
  eq(parseRequest({ op: 'autocomplete', q: 'x'.repeat(81) }), 'bad_query');
  eq(parseRequest({ op: 'autocomplete', q: ' حمص\u0000 ', lang: 'fr' }), { op: 'autocomplete', q: 'حمص', lang: 'ar', near: undefined });
  eq(parseRequest({ op: 'autocomplete', q: 'حمص', near: { lat: 52.5, lon: 13.4 } }), 'bad_point');
  eq(parseRequest({ op: 'reverse', lat: 52.5, lon: 13.4 }), 'outside_syria');
  eq(parseRequest({ op: 'reverse', lat: '35.5', lon: 35.8, lang: 'de' }), { op: 'reverse', at: { lat: 35.5, lon: 35.8 }, lang: 'de' });
  eq(parseRequest({ op: 'route', points: [{ lat: 35, lon: 36 }] }), 'bad_points');
  eq(parseRequest({ op: 'route', points: Array(7).fill({ lat: 35, lon: 36 }) }), 'bad_points');
  eq(parseRequest({ op: 'route', points: [{ lat: 35, lon: 36 }, { lat: 'x', lon: 1 }] }), 'outside_syria');
  eq(parseRequest({ op: 'route', points: [{ lat: 35, lon: 36 }, { lat: 34, lon: 37 }], alternatives: 'yes' }),
    { op: 'route', points: [{ lat: 35, lon: 36 }, { lat: 34, lon: 37 }], alternatives: false });
});

Deno.test('مفتاح الكاش: نقاط متقاربة جداً = نفس المفتاح', () => {
  const a = parseRequest({ op: 'reverse', lat: 35.51961, lon: 35.78321 });
  const b = parseRequest({ op: 'reverse', lat: 35.51959, lon: 35.78319 });
  eq(cacheKey('ors', a as never), cacheKey('ors', b as never));
  const c = parseRequest({ op: 'autocomplete', q: 'Homs' });
  const d = parseRequest({ op: 'autocomplete', q: 'homs' });
  eq(cacheKey('ors', c as never), cacheKey('ors', d as never));
  ok(cacheKey('ors', c as never) !== cacheKey('osm', c as never), 'provider in key');
});

Deno.test('المزود التجريبي بيعطي مسار وبديل', async () => {
  const p = fakeProvider();
  const r = await p.route([{ lat: 35.52, lon: 35.78 }, { lat: 34.73, lon: 36.71 }], true);
  eq(r.length, 2);
  ok(r[0].distance_m > 100000 && r[0].duration_s > 0, 'plausible');
});
