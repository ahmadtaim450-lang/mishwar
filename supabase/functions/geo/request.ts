// التحقق من طلبات دالة الخرائط ومفتاح الكاش (منفصل لحتى ينفحص لحالو).
import { inSyria, type Lang, type Pt } from './providers.ts';

export type GeoReq =
  | { op: 'autocomplete'; q: string; lang: Lang; near?: Pt }
  | { op: 'geocode'; q: string; lang: Lang }
  | { op: 'reverse'; at: Pt; lang: Lang }
  | { op: 'route'; points: Pt[]; alternatives: boolean };

const LANGS = new Set(['ar', 'en', 'de']);

function pt(v: any): Pt | null {
  const lat = Number(v?.lat), lon = Number(v?.lon);
  if (!Number.isFinite(lat) || !Number.isFinite(lon)) return null;
  return { lat, lon };
}

// بيرجّع الطلب نظيف أو رسالة الخطأ
export function parseRequest(body: any): GeoReq | string {
  if (!body || typeof body !== 'object') return 'bad_request';
  const lang = (LANGS.has(body.lang) ? body.lang : 'ar') as Lang;
  switch (body.op) {
    case 'autocomplete':
    case 'geocode': {
      const q = typeof body.q === 'string' ? body.q.replace(/[\u0000-\u001f]/g, ' ').trim() : '';
      if (q.length < 2 || q.length > 80) return 'bad_query';
      if (body.op === 'geocode') return { op: 'geocode', q, lang };
      const near = body.near == null ? undefined : pt(body.near);
      if (near === null || (near && !inSyria(near))) return 'bad_point';
      return { op: 'autocomplete', q, lang, near };
    }
    case 'reverse': {
      const at = pt(body);
      if (!at || !inSyria(at)) return 'outside_syria';
      return { op: 'reverse', at, lang };
    }
    case 'route': {
      if (!Array.isArray(body.points) || body.points.length < 2 || body.points.length > 6) return 'bad_points';
      const points: Pt[] = [];
      for (const p of body.points) {
        const v = pt(p);
        if (!v || !inSyria(v)) return 'outside_syria';
        points.push(v);
      }
      return { op: 'route', points, alternatives: body.alternatives === true };
    }
    default:
      return 'bad_op';
  }
}

// تقريب الإحداثيات لـ 4 خانات (~11 متر) لحتى الكاش يفيد
const r4 = (x: number) => x.toFixed(4);
const k = (p: Pt) => `${r4(p.lat)},${r4(p.lon)}`;

export function cacheKey(provider: string, r: GeoReq): string {
  switch (r.op) {
    case 'autocomplete': return `${provider}:ac:${r.lang}:${r.q.toLowerCase()}:${r.near ? `${r.near.lat.toFixed(1)},${r.near.lon.toFixed(1)}` : '-'}`;
    case 'geocode': return `${provider}:gc:${r.lang}:${r.q.toLowerCase()}`;
    case 'reverse': return `${provider}:rv:${r.lang}:${k(r.at)}`;
    case 'route': return `${provider}:rt:${r.alternatives ? 1 : 0}:${r.points.map(k).join(';')}`;
  }
}

// مدة صلاحية الكاش بالساعات: الطرق بتتغير أسرع من أسماء الأماكن
export const ttlHours = (r: GeoReq) => (r.op === 'route' ? 24 : 24 * 7);
