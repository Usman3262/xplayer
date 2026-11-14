/**
 * List state lives in the URL (?page=2&q=foo&action=update) so links, back/forward
 * and refresh keep the view. Parsed leniently: bad values fall back to defaults.
 */
export type SearchParamsRecord = Record<string, string | string[] | undefined>;

export type TableParams = {
  page: number;
  pageSize: number;
  q: string;
  /** Other single-value filters (string) from the URL. */
  filters: Record<string, string>;
};

const first = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v);

export function parseTableParams(
  sp: SearchParamsRecord,
  { filterKeys = [] as string[], defaultPageSize = 25, maxPageSize = 100 } = {},
): TableParams {
  const page = Math.max(1, Number.parseInt(first(sp.page) ?? "1", 10) || 1);
  const size = Number.parseInt(first(sp.size) ?? "", 10);
  const pageSize = Number.isFinite(size) ? Math.min(maxPageSize, Math.max(5, size)) : defaultPageSize;
  const q = (first(sp.q) ?? "").trim().slice(0, 100);
  const filters: Record<string, string> = {};
  for (const k of filterKeys) {
    const v = first(sp[k])?.trim();
    if (v) filters[k] = v.slice(0, 100);
  }
  return { page, pageSize, q, filters };
}

/** Build a list URL keeping current params, with overrides (null = remove). */
export function withParams(path: string, current: SearchParamsRecord, overrides: Record<string, string | number | null>): string {
  const p = new URLSearchParams();
  for (const [k, v] of Object.entries(current)) {
    const val = first(v);
    if (val) p.set(k, val);
  }
  for (const [k, v] of Object.entries(overrides)) {
    if (v === null || v === "") p.delete(k);
    else p.set(k, String(v));
  }
  const s = p.toString();
  return s ? `${path}?${s}` : path;
}

/** ISO timestamp `days` ago (for "last N days" filters), or undefined. */
export function sinceDaysIso(days: number | undefined): string | undefined {
  return days ? new Date(Date.now() - days * 864e5).toISOString() : undefined;
}
