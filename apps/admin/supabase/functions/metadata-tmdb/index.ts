// metadata-tmdb — metadata ON DEMAND (server-side only; the TMDB key never
// reaches the apps). Panels are huge (Neo ≈ 60k movies + 70k series), so nothing
// is bulk-imported: the app asks only for titles a user is looking at, and each
// title is fetched from TMDB once and then served from the global catalog.
// What to show (rails, Top 10) comes from the user's panel — never TMDB lists.
//
// POST JSON { action, ... }
//   resolve  (apps, anyone)   { items: [{ kind: "movie"|"series", tmdb_id?, title?, year? }] }  ≤ 25
//                             Send tmdb_id when the panel provides it (Neo/Xtream often does).
//   season   (apps, anyone)   { tmdb_id, season }                       → episodes
//   refresh  (admin)          { kind, tmdb_id }                         → force re-fetch
//
// Admin = signed-in user with catalog.write, or the service/secret key (cron).

import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";

import { type Kind, LANG, PUBLIC_FIELDS, syncMovie, syncSeason, syncSeries, tmdbType } from "./catalog.ts";
import { cleanTitle, pickMatch, type Candidate } from "./titles.ts";
import { pMap, tmdb, TmdbNotFound } from "./tmdb.ts";

const URL_ = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const MAX_ITEMS = 25;
const STALE_MS = 30 * 864e5;

const db: SupabaseClient = createClient(URL_, SERVICE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

const cors = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, apikey, content-type, x-client-info",
  "access-control-allow-methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "content-type": "application/json" } });

class HttpError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

// ── auth ─────────────────────────────────────────────────────────────────────
async function requireAdmin(req: Request) {
  const token = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "").trim();
  if (!token) throw new HttpError(401, "sign in required");
  if (token === SERVICE_KEY) return;
  if (token.startsWith("sb_secret_")) {
    // New-style secret key: valid only if it can use the admin API.
    const probe = createClient(URL_, token, { auth: { persistSession: false } });
    const { error } = await probe.auth.admin.listUsers({ page: 1, perPage: 1 });
    if (!error) return;
    throw new HttpError(401, "invalid key");
  }
  const userDb = createClient(URL_, ANON_KEY, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { persistSession: false },
  });
  const { data: { user } } = await userDb.auth.getUser(token);
  if (!user) throw new HttpError(401, "invalid session");
  const { data: ok } = await userDb.rpc("has_permission", { perm: "catalog.write" });
  if (!ok) throw new HttpError(403, "catalog.write required");
}

// ── resolve ──────────────────────────────────────────────────────────────────
interface Item { kind: Kind; tmdb_id?: number; title?: string; year?: number }

const table = (k: Kind) => (k === "movie" ? "global_movies" : "global_series");
const sync = (k: Kind, id: number) => (k === "movie" ? syncMovie(db, id) : syncSeries(db, id));

async function missRetryDays(): Promise<number> {
  const { data } = await db.from("app_settings").select("value").eq("key", "metadata.miss_retry_days").maybeSingle();
  return Number(data?.value ?? 7) || 7;
}

async function resolveOne(item: Item, retryDays: number) {
  const kind: Kind = item.kind === "series" ? "series" : "movie";

  if (item.tmdb_id) {
    const { data } = await db.from(table(kind)).select(`${PUBLIC_FIELDS},fetched_at`)
      .eq("tmdb_id", item.tmdb_id).maybeSingle();
    if (data && data.fetched_at && Date.now() - Date.parse(data.fetched_at) < STALE_MS) {
      const { fetched_at: _, ...rest } = data;
      return { kind, ...rest };
    }
    try {
      return await sync(kind, item.tmdb_id);
    } catch (e) {
      if (e instanceof TmdbNotFound) return null;
      throw e;
    }
  }

  const { title, year: parsedYear } = cleanTitle(item.title ?? "");
  const year = item.year || parsedYear;
  if (title.length < 2) return null;
  const titleNorm = title.toLowerCase();

  // 1. Already in the catalog?
  let q = db.from(table(kind)).select(PUBLIC_FIELDS).eq("title_norm", titleNorm);
  if (year) q = q.gte("year", year - 1).lte("year", year + 1);
  const { data: local } = await q.order("popularity", { ascending: false, nullsFirst: false }).limit(1);
  if (local?.length) return { kind, ...local[0] };

  // 2. Recently not found?
  const { data: miss } = await db.from("metadata_misses").select("checked_at")
    .eq("kind", kind).eq("title_norm", titleNorm).eq("year", year ?? 0).maybeSingle();
  if (miss && Date.now() - Date.parse(miss.checked_at) < retryDays * 864e5) return null;

  // 3. Ask TMDB (strict match only).
  const res = await tmdb<{ results: Candidate[] }>(`/search/${tmdbType(kind)}`, {
    query: title, language: LANG, include_adult: "false",
  });
  const hit = pickMatch(title, year, res.results ?? []);
  if (!hit) {
    await db.from("metadata_misses").upsert(
      { kind, title_norm: titleNorm, year: year ?? 0, checked_at: new Date().toISOString() },
      { onConflict: "kind,title_norm,year" },
    );
    return null;
  }
  return await sync(kind, hit.id);
}

async function resolve(items: Item[]) {
  if (!Array.isArray(items) || items.length === 0) throw new HttpError(400, "items required");
  if (items.length > MAX_ITEMS) throw new HttpError(400, `max ${MAX_ITEMS} items`);
  const retryDays = await missRetryDays();
  // Same title twice in one request → one lookup.
  const keyOf = (i: Item) => `${i.kind}|${i.tmdb_id ?? ""}|${(i.title ?? "").toLowerCase()}|${i.year ?? ""}`;
  const unique = [...new Map(items.map((i) => [keyOf(i), i])).values()];
  const results = await pMap(unique, 4, async (i) => {
    try {
      return [keyOf(i), await resolveOne(i, retryDays)] as const;
    } catch (e) {
      console.error("resolve failed", (e as Error).message);
      return [keyOf(i), null] as const;
    }
  });
  const byKey = new Map(results);
  return { results: items.map((i) => byKey.get(keyOf(i)) ?? null) };
}

// ── router ───────────────────────────────────────────────────────────────────
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);
  try {
    const body = await req.json().catch(() => ({}));
    switch (body.action) {
      case "resolve":
        return json(await resolve(body.items));
      case "season": {
        const id = Number(body.tmdb_id);
        const season = Number(body.season);
        if (!id || !Number.isInteger(season) || season < 0) throw new HttpError(400, "tmdb_id and season required");
        return json(await syncSeason(db, id, season));
      }
      case "refresh": {
        await requireAdmin(req);
        const kind: Kind = body.kind === "series" ? "series" : "movie";
        if (!Number(body.tmdb_id)) throw new HttpError(400, "tmdb_id required");
        return json(await sync(kind, Number(body.tmdb_id)));
      }
      default:
        throw new HttpError(400, "unknown action");
    }
  } catch (e) {
    if (e instanceof HttpError) return json({ error: e.message }, e.status);
    if (e instanceof TmdbNotFound) return json({ error: "not found on TMDB" }, 404);
    console.error(e);
    return json({ error: "internal error" }, 500);
  }
});
