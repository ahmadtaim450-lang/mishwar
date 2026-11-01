// مزودات الخرائط: بحث، عنوان من إحداثيات، ومسارات.
// كل مزود بيرجّع نفس الشكل، فالتطبيق ما بيعرف مين المزود.
//
//  · ors   : OpenRouteService — بدو ORS_API_KEY (فيه باقة مجانية بحدود يومية)
//  · osm   : Photon + Nominatim + OSRM العامة — بلا مفتاح، للتطوير والتجربة بس
//            (سياسات الاستعمال العادل ما بتسمح بحمل إنتاجي)
//  · fake  : بيانات ثابتة للاختبارات الآلية بس

export type Lang = 'ar' | 'en' | 'de';
export interface Pt { lat: number; lon: number }
export interface Place { name: string; label: string; lat: number; lon: number; kind: string; source: string }
export interface Route { distance_m: number; duration_s: number; geometry: [number, number][]; summary: string }

export interface Provider {
  id: string;
  autocomplete(q: string, lang: Lang, near?: Pt): Promise<Place[]>;
  geocode(q: string, lang: Lang): Promise<Place[]>;
  reverse(p: Pt, lang: Lang): Promise<Place | null>;
  route(points: Pt[], alternatives: boolean): Promise<Route[]>;
}

export type Fetch = (url: string, init?: RequestInit) => Promise<Response>;

// حدود سوريا (lon/lat) لحصر البحث
export const SY_BBOX = { minLon: 35.5, minLat: 32.2, maxLon: 42.5, maxLat: 37.4 };
export const inSyria = (p: Pt) => p.lat >= SY_BBOX.minLat && p.lat <= SY_BBOX.maxLat && p.lon >= SY_BBOX.minLon && p.lon <= SY_BBOX.maxLon;

export class ProviderError extends Error {
  constructor(public status: number, msg: string) { super(msg); }
}

async function getJson(f: Fetch, url: string, init?: RequestInit): Promise<any> {
  const res = await f(url, { ...init, signal: AbortSignal.timeout(8000) });
  if (res.status === 429) throw new ProviderError(429, 'provider_rate_limited');
  if (!res.ok) throw new ProviderError(res.status, `provider_http_${res.status}`);
  return await res.json();
}

const num = (v: unknown) => (typeof v === 'number' ? v : Number(v));
const validPt = (lat: number, lon: number) => Number.isFinite(lat) && Number.isFinite(lon) && Math.abs(lat) <= 90 && Math.abs(lon) <= 180;

// ── تحويل الردود (منفصل عن الشبكة لحتى ينفحص) ─────────────────────────
export function parsePelias(j: any, source: string): Place[] {
  const out: Place[] = [];
  for (const f of j?.features ?? []) {
    const [lon, lat] = f?.geometry?.coordinates ?? [];
    const p = f?.properties ?? {};
    if (!validPt(num(lat), num(lon)) || !p.name) continue;
    out.push({ name: String(p.name), label: String(p.label ?? p.name), lat: num(lat), lon: num(lon), kind: String(p.layer ?? 'place'), source });
  }
  return out;
}

export function parsePhoton(j: any): Place[] {
  const out: Place[] = [];
  for (const f of j?.features ?? []) {
    const [lon, lat] = f?.geometry?.coordinates ?? [];
    const p = f?.properties ?? {};
    if (!validPt(num(lat), num(lon)) || !p.name) continue;
    if (p.countrycode && String(p.countrycode).toUpperCase() !== 'SY') continue;
    const parts = [p.name, p.city ?? p.county, p.state].filter((x: unknown, i: number, a: unknown[]) => x && a.indexOf(x) === i);
    out.push({ name: String(p.name), label: parts.join('، '), lat: num(lat), lon: num(lon), kind: String(p.osm_value ?? p.type ?? 'place'), source: 'photon' });
  }
  return out;
}

export function parseNominatim(j: any): Place | null {
  const lat = num(j?.lat), lon = num(j?.lon);
  if (!validPt(lat, lon) || j?.error) return null;
  const a = j.address ?? {};
  const name = j.name || a.road || a.neighbourhood || a.suburb || a.village || a.town || a.city || j.display_name;
  if (!name) return null;
  const parts = [name, a.suburb ?? a.neighbourhood, a.city ?? a.town ?? a.village, a.state].filter((x: unknown, i: number, arr: unknown[]) => x && arr.indexOf(x) === i);
  return { name: String(name), label: parts.join('، '), lat, lon, kind: String(j.type ?? j.category ?? 'place'), source: 'nominatim' };
}

const toLatLon = (coords: any[]): [number, number][] =>
  coords.filter((c) => Array.isArray(c) && validPt(num(c[1]), num(c[0]))).map((c) => [round5(num(c[1])), round5(num(c[0]))]);
const round5 = (x: number) => Math.round(x * 1e5) / 1e5;

export function parseOrsRoute(j: any): Route[] {
  const out: Route[] = [];
  for (const f of j?.features ?? []) {
    const s = f?.properties?.summary ?? {};
    const g = toLatLon(f?.geometry?.coordinates ?? []);
    if (g.length < 2) continue;
    out.push({ distance_m: Math.round(num(s.distance ?? 0)), duration_s: Math.round(num(s.duration ?? 0)), geometry: g, summary: '' });
  }
  return out;
}

export function parseOsrm(j: any): Route[] {
  if (j?.code && j.code !== 'Ok') {
    if (j.code === 'NoRoute') return [];
    throw new ProviderError(502, `osrm_${j.code}`);
  }
  const out: Route[] = [];
  for (const r of j?.routes ?? []) {
    const g = toLatLon(r?.geometry?.coordinates ?? []);
    if (g.length < 2) continue;
    const summary = (r?.legs ?? []).map((l: any) => l?.summary).filter(Boolean).join(' · ');
    out.push({ distance_m: Math.round(num(r.distance)), duration_s: Math.round(num(r.duration)), geometry: g, summary });
  }
  return out;
}

// ── المزودات ───────────────────────────────────────────────────────
export function orsProvider(key: string, f: Fetch = fetch): Provider {
  const base = 'https://api.openrouteservice.org';
  const common = (lang: Lang) =>
    `api_key=${encodeURIComponent(key)}&lang=${lang}&boundary.country=SY&boundary.rect.min_lon=${SY_BBOX.minLon}&boundary.rect.min_lat=${SY_BBOX.minLat}&boundary.rect.max_lon=${SY_BBOX.maxLon}&boundary.rect.max_lat=${SY_BBOX.maxLat}`;
  return {
    id: 'ors',
    async autocomplete(q, lang, near) {
      const focus = near ? `&focus.point.lat=${near.lat}&focus.point.lon=${near.lon}` : '';
      return parsePelias(await getJson(f, `${base}/geocode/autocomplete?${common(lang)}&text=${encodeURIComponent(q)}${focus}`), 'ors');
    },
    async geocode(q, lang) {
      return parsePelias(await getJson(f, `${base}/geocode/search?${common(lang)}&size=8&text=${encodeURIComponent(q)}`), 'ors');
    },
    async reverse(p, lang) {
      const r = parsePelias(await getJson(f, `${base}/geocode/reverse?api_key=${encodeURIComponent(key)}&lang=${lang}&size=1&point.lat=${p.lat}&point.lon=${p.lon}`), 'ors');
      return r[0] ?? null;
    },
    async route(points, alternatives) {
      const body: Record<string, unknown> = { coordinates: points.map((p) => [p.lon, p.lat]), instructions: false };
      // ORS بيسمح بالمسارات البديلة بس بين نقطتين
      if (alternatives && points.length === 2) body.alternative_routes = { target_count: 3, share_factor: 0.6, weight_factor: 1.6 };
      try {
        return parseOrsRoute(await getJson(f, `${base}/v2/directions/driving-car/geojson`, {
          method: 'POST',
          headers: { Authorization: key, 'Content-Type': 'application/json', Accept: 'application/geo+json' },
          body: JSON.stringify(body),
        }));
      } catch (e) {
        // 404 = ما في طريق بين النقاط
        if (e instanceof ProviderError && e.status === 404) return [];
        throw e;
      }
    },
  };
}

export function osmProvider(contact: string, f: Fetch = fetch): Provider {
  const ua = { 'User-Agent': `Mishwar/1.0 (${contact})` };
  const photonLang = (l: Lang) => (l === 'ar' ? 'default' : l); // Photon ما بيدعم العربي، "default" = الأسماء المحلية
  const bbox = `${SY_BBOX.minLon},${SY_BBOX.minLat},${SY_BBOX.maxLon},${SY_BBOX.maxLat}`;
  return {
    id: 'osm',
    async autocomplete(q, lang, near) {
      const focus = near ? `&lat=${near.lat}&lon=${near.lon}` : '';
      return parsePhoton(await getJson(f, `https://photon.komoot.io/api/?q=${encodeURIComponent(q)}&lang=${photonLang(lang)}&limit=8&bbox=${bbox}${focus}`, { headers: ua }));
    },
    async geocode(q, lang) {
      return parsePhoton(await getJson(f, `https://photon.komoot.io/api/?q=${encodeURIComponent(q)}&lang=${photonLang(lang)}&limit=8&bbox=${bbox}`, { headers: ua }));
    },
    async reverse(p, lang) {
      return parseNominatim(await getJson(f, `https://nominatim.openstreetmap.org/reverse?format=jsonv2&addressdetails=1&zoom=17&lat=${p.lat}&lon=${p.lon}&accept-language=${lang}`, { headers: ua }));
    },
    async route(points, alternatives) {
      const coords = points.map((p) => `${p.lon},${p.lat}`).join(';');
      const alt = alternatives && points.length === 2 ? 'true' : 'false';
      return parseOsrm(await getJson(f, `https://router.project-osrm.org/route/v1/driving/${coords}?overview=full&geometries=geojson&alternatives=${alt}&steps=false`, { headers: ua }));
    },
  };
}

// للاختبارات الآلية بس: بيرجّع نتائج ثابتة ومنطقية بلا شبكة
export function fakeProvider(): Provider {
  let calls = 0;
  const homs = { name: 'حمص', label: 'حمص، سوريا', lat: 34.7324, lon: 36.7137, kind: 'locality', source: 'fake' };
  return {
    id: 'fake',
    get calls() { return calls; },
    async autocomplete(q) { calls++; return q.includes('حم') ? [homs] : []; },
    async geocode(q) { calls++; return q.includes('حم') ? [homs] : []; },
    async reverse(p) { calls++; return { ...homs, name: 'شارع تجريبي', lat: p.lat, lon: p.lon, kind: 'street' }; },
    async route(points, alternatives) {
      calls++;
      const a = points[0], b = points[points.length - 1];
      const line: [number, number][] = points.map((p) => [p.lat, p.lon]);
      const d = haversine(a, b);
      const main: Route = { distance_m: Math.round(d * 1.3), duration_s: Math.round(d * 1.3 / 22), geometry: line, summary: 'M5' };
      if (!alternatives || points.length !== 2) return [main];
      const mid: Pt = { lat: (a.lat + b.lat) / 2 + 0.1, lon: (a.lon + b.lon) / 2 + 0.1 };
      return [main, { distance_m: Math.round(d * 1.5), duration_s: Math.round(d * 1.5 / 20), geometry: [[a.lat, a.lon], [mid.lat, mid.lon], [b.lat, b.lon]], summary: 'بديل' }];
    },
  } as Provider;
}

export function haversine(a: Pt, b: Pt): number {
  const r = 6371000, rad = Math.PI / 180;
  const dLat = (b.lat - a.lat) * rad, dLon = (b.lon - a.lon) * rad;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(a.lat * rad) * Math.cos(b.lat * rad) * Math.sin(dLon / 2) ** 2;
  return 2 * r * Math.asin(Math.sqrt(h));
}

export function pickProvider(env: (k: string) => string | undefined, f: Fetch = fetch): Provider {
  const id = env('GEO_PROVIDER') ?? (env('ORS_API_KEY') ? 'ors' : 'osm');
  if (id === 'ors') {
    const key = env('ORS_API_KEY');
    if (!key) throw new Error('ORS_API_KEY missing');
    return orsProvider(key, f);
  }
  if (id === 'fake') return fakeProvider();
  return osmProvider(env('GEO_CONTACT') ?? 'https://github.com/ahmadtaim450-lang/mishwar', f);
}
