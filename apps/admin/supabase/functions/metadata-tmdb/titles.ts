// Turn messy panel names ("EN - Interstellar (2014) 4K HEVC") into title + year,
// and decide whether a TMDB result is a safe match (never merge look-alikes).

const QUALITY =
  /\b(4k|8k|uhd|fhd|hd|sd|hevc|h\.?26[45]|x26[45]|2160p|1080p|720p|480p|hdr(10)?\+?|dolby ?vision|dv|multi|multi-?sub|vostfr|vf|dual ?audio|web-?dl|webrip|bluray|brrip|hdrip|dvdrip|cam|hdcam|ts)\b/gi;

export function cleanTitle(raw: string): { title: string; year?: number } {
  let t = (raw ?? "").trim();
  t = t.replace(/^\|[^|]{1,8}\|\s*/, ""); //            "|EN| Title"
  t = t.replace(/^[\[(]?[A-Z]{2,4}[\])]?\s*[-:|]\s+/, ""); // "EN - Title", "[AR] : Title"
  let year: number | undefined;
  const m =
    t.match(/[\[(]\s*((?:19|20)\d{2})\s*[\])]/) ??
    t.match(/\s[-–]\s*((?:19|20)\d{2})\s*$/) ??
    t.match(/\s((?:19|20)\d{2})\s*$/);
  if (m) {
    year = Number(m[1]);
    t = t.replace(m[0], " ");
  }
  t = t
    .replace(QUALITY, " ")
    .replace(/[\[(][^\])]*[\])]/g, " ")
    .replace(/[._]+/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .replace(/[-:|–\s]+$/, "")
    .trim();
  return { title: t, year };
}

/** Loose key for comparing titles across languages/punctuation. */
export function normKey(s: string): string {
  return (s ?? "")
    .toLowerCase()
    .normalize("NFKD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/&/g, "and")
    .replace(/^(the|a|an)\s+/, "")
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

export interface Candidate {
  id: number;
  title?: string;
  name?: string;
  original_title?: string;
  original_name?: string;
  release_date?: string;
  first_air_date?: string;
  popularity?: number;
}

/** Confident match only: same normalised title and (if known) year within ±1. */
export function pickMatch(query: string, year: number | undefined, results: Candidate[]): Candidate | null {
  const q = normKey(query);
  if (!q) return null;
  for (const r of results.slice(0, 10)) {
    const names = [r.title, r.name, r.original_title, r.original_name].filter(Boolean) as string[];
    const sameTitle = names.some((n) => normKey(n) === q);
    if (!sameTitle) continue;
    const d = r.release_date || r.first_air_date;
    const ry = d ? Number(d.slice(0, 4)) : undefined;
    if (year && ry && Math.abs(ry - year) > 1) continue;
    return r;
  }
  return null;
}
