// Minimal TMDB v3 client. Key from the TMDB_API_KEY secret (v3 key or v4 read token).

const BASE = "https://api.themoviedb.org/3";
const KEY = Deno.env.get("TMDB_API_KEY") ?? "";

export class TmdbNotFound extends Error {}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

export async function tmdb<T>(
  path: string,
  params: Record<string, string | number | undefined> = {},
): Promise<T> {
  if (!KEY) throw new Error("TMDB_API_KEY secret is not set");
  const url = new URL(BASE + path);
  for (const [k, v] of Object.entries(params)) {
    if (v !== undefined && v !== "") url.searchParams.set(k, String(v));
  }
  const headers: Record<string, string> = { accept: "application/json" };
  if (KEY.startsWith("eyJ")) headers.authorization = `Bearer ${KEY}`;
  else url.searchParams.set("api_key", KEY);

  for (let attempt = 0; attempt < 3; attempt++) {
    const res = await fetch(url, { headers, signal: AbortSignal.timeout(10_000) });
    if (res.status === 429) {
      await sleep((Number(res.headers.get("retry-after")) || 1) * 1000);
      continue;
    }
    if (res.status === 404) throw new TmdbNotFound(path);
    if (!res.ok) throw new Error(`TMDB ${res.status} on ${path}`);
    return (await res.json()) as T;
  }
  throw new Error("TMDB rate limit");
}

/** Run `fn` over `items` with at most `limit` in flight. */
export async function pMap<I, O>(items: I[], limit: number, fn: (i: I) => Promise<O>): Promise<O[]> {
  const out = new Array<O>(items.length);
  let next = 0;
  const worker = async () => {
    while (next < items.length) {
      const i = next++;
      out[i] = await fn(items[i]);
    }
  };
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, worker));
  return out;
}
