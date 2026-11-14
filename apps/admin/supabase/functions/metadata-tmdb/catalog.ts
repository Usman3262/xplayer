// Write TMDB details into the global catalog. Never overwrites `locked_fields`
// (fields an admin edited). Service-role client only.

import type { SupabaseClient } from "npm:@supabase/supabase-js@2";

import { tmdb } from "./tmdb.ts";

export type Kind = "movie" | "series";
export const tmdbType = (k: Kind) => (k === "movie" ? "movie" : "tv");
export const LANG = Deno.env.get("TMDB_LANGUAGE") ?? "en-US";

export const PUBLIC_FIELDS =
  "id,tmdb_id,title,year,overview,poster_path,backdrop_path,logo_path,rating,trailer_youtube";

// deno-lint-ignore no-explicit-any
type Json = any;

const round1 = (n?: number) => (typeof n === "number" ? Math.round(n * 10) / 10 : null);
const orNull = <T>(v: T | "" | undefined | null) => (v === "" || v === undefined ? null : v);

function trailer(videos: Json): string | null {
  const list: Json[] = videos?.results ?? [];
  const yt = list.filter((v) => v.site === "YouTube");
  const best = yt.find((v) => v.type === "Trailer" && v.official) ?? yt.find((v) => v.type === "Trailer") ?? yt[0];
  return best?.key ?? null;
}

function logo(images: Json): string | null {
  const logos: Json[] = images?.logos ?? [];
  return (logos.find((l) => l.iso_639_1 === "en") ?? logos[0])?.file_path ?? null;
}

function credits(c: Json, createdBy?: Json[]) {
  return {
    cast: (c?.cast ?? []).slice(0, 15).map((p: Json) => ({
      name: p.name, character: p.character ?? null, profile: p.profile_path ?? null,
    })),
    directors: [
      ...(c?.crew ?? []).filter((p: Json) => p.job === "Director").map((p: Json) => p.name),
      ...(createdBy ?? []).map((p: Json) => p.name),
    ].slice(0, 5),
  };
}

function movieCert(rd: Json): string | null {
  for (const country of ["US", "GB"]) {
    const r = rd?.results?.find((x: Json) => x.iso_3166_1 === country);
    const c = r?.release_dates?.find((d: Json) => d.certification)?.certification;
    if (c) return c;
  }
  return null;
}

function tvCert(cr: Json): string | null {
  return cr?.results?.find((x: Json) => x.iso_3166_1 === "US")?.rating ?? null;
}

async function upsertGenres(db: SupabaseClient, genres: Json[]): Promise<number[]> {
  if (!genres?.length) return [];
  const rows = genres.map((g: Json) => ({
    tmdb_id: g.id,
    name: g.name,
    slug: String(g.name).toLowerCase().normalize("NFKD").replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "") || `g${g.id}`,
  }));
  const { data, error } = await db.from("genres").upsert(rows, { onConflict: "tmdb_id" }).select("id");
  if (error) throw error;
  return (data ?? []).map((r) => r.id as number);
}

/** Insert or update one row keyed by tmdb_id, skipping locked fields. */
async function upsertLocked(db: SupabaseClient, table: string, row: Record<string, unknown>) {
  const { data: existing, error: e1 } = await db
    .from(table).select("id, locked_fields").eq("tmdb_id", row.tmdb_id as number).maybeSingle();
  if (e1) throw e1;
  const locked: string[] = existing?.locked_fields ?? [];
  for (const f of locked) delete row[f];

  const write = (r: Record<string, unknown>) =>
    existing
      ? db.from(table).update(r).eq("id", existing.id).select(PUBLIC_FIELDS).single()
      : db.from(table).insert(r).select(PUBLIC_FIELDS).single();

  let res = await write(row);
  // imdb_id is unique; a TMDB duplicate entry can collide — keep the row without it.
  if (res.error?.code === "23505" && row.imdb_id) {
    res = await write({ ...row, imdb_id: null });
  }
  if (res.error) throw res.error;
  return { row: res.data as Record<string, unknown>, locked };
}

async function setGenres(db: SupabaseClient, join: string, col: string, id: string, genreIds: number[], locked: string[]) {
  if (locked.includes("genres")) return;
  await db.from(join).delete().eq(col, id);
  if (genreIds.length) {
    const { error } = await db.from(join).insert(genreIds.map((g) => ({ [col]: id, genre_id: g })));
    if (error) throw error;
  }
}

export async function syncMovie(db: SupabaseClient, tmdbId: number) {
  const d: Json = await tmdb(`/movie/${tmdbId}`, {
    language: LANG,
    append_to_response: "credits,videos,release_dates,images",
    include_image_language: "en,null",
  });
  const { row, locked } = await upsertLocked(db, "global_movies", {
    tmdb_id: d.id,
    imdb_id: /^tt\d+$/.test(d.imdb_id ?? "") ? d.imdb_id : null,
    title: d.title || d.original_title,
    original_title: orNull(d.original_title),
    original_language: orNull(d.original_language),
    overview: orNull(d.overview),
    tagline: orNull(d.tagline),
    release_date: orNull(d.release_date),
    runtime_min: d.runtime || null,
    certification: movieCert(d.release_dates),
    poster_path: d.poster_path ?? null,
    backdrop_path: d.backdrop_path ?? null,
    logo_path: logo(d.images),
    trailer_youtube: trailer(d.videos),
    rating: round1(d.vote_average),
    vote_count: d.vote_count ?? null,
    popularity: d.popularity ?? null,
    credits: credits(d.credits),
    countries: (d.production_countries ?? []).map((c: Json) => c.iso_3166_1),
    adult: !!d.adult,
    metadata_source: "tmdb",
    fetched_at: new Date().toISOString(),
  });
  await setGenres(db, "movie_genres", "movie_id", row.id as string, await upsertGenres(db, d.genres), locked);
  return { kind: "movie" as const, ...row };
}

export async function syncSeries(db: SupabaseClient, tmdbId: number) {
  const d: Json = await tmdb(`/tv/${tmdbId}`, {
    language: LANG,
    append_to_response: "credits,videos,content_ratings,external_ids,images",
    include_image_language: "en,null",
  });
  const imdb = d.external_ids?.imdb_id;
  const { row, locked } = await upsertLocked(db, "global_series", {
    tmdb_id: d.id,
    imdb_id: /^tt\d+$/.test(imdb ?? "") ? imdb : null,
    title: d.name || d.original_name,
    original_title: orNull(d.original_name),
    original_language: orNull(d.original_language),
    overview: orNull(d.overview),
    first_air_date: orNull(d.first_air_date),
    last_air_date: orNull(d.last_air_date),
    status: orNull(d.status),
    season_count: d.number_of_seasons ?? null,
    episode_count: d.number_of_episodes ?? null,
    certification: tvCert(d.content_ratings),
    poster_path: d.poster_path ?? null,
    backdrop_path: d.backdrop_path ?? null,
    logo_path: logo(d.images),
    trailer_youtube: trailer(d.videos),
    rating: round1(d.vote_average),
    vote_count: d.vote_count ?? null,
    popularity: d.popularity ?? null,
    credits: credits(d.credits, d.created_by),
    countries: d.origin_country ?? [],
    adult: !!d.adult,
    metadata_source: "tmdb",
    fetched_at: new Date().toISOString(),
  });
  const seriesId = row.id as string;
  await setGenres(db, "series_genres", "series_id", seriesId, await upsertGenres(db, d.genres), locked);

  // Seasons (skip seasons an admin locked entirely).
  const { data: existing } = await db.from("global_seasons")
    .select("season_number, locked_fields").eq("series_id", seriesId);
  const lockedSeasons = new Set((existing ?? []).filter((s) => (s.locked_fields ?? []).length).map((s) => s.season_number));
  const seasons = (d.seasons ?? [])
    .filter((s: Json) => !lockedSeasons.has(s.season_number))
    .map((s: Json) => ({
      series_id: seriesId,
      season_number: s.season_number,
      name: orNull(s.name),
      overview: orNull(s.overview),
      poster_path: s.poster_path ?? null,
      air_date: orNull(s.air_date),
      episode_count: s.episode_count ?? null,
    }));
  if (seasons.length) {
    const { error } = await db.from("global_seasons").upsert(seasons, { onConflict: "series_id,season_number" });
    if (error) throw error;
  }
  return { kind: "series" as const, ...row };
}

/** Episodes of one season (fetched once, then served from the DB). */
export async function syncSeason(db: SupabaseClient, seriesTmdbId: number, seasonNumber: number, force = false) {
  let { data: series } = await db.from("global_series").select("id").eq("tmdb_id", seriesTmdbId).maybeSingle();
  if (!series) series = { id: String((await syncSeries(db, seriesTmdbId) as Record<string, unknown>).id) };

  const { data: season } = await db.from("global_seasons")
    .select("id, updated_at").eq("series_id", series.id).eq("season_number", seasonNumber).maybeSingle();
  const fresh = season && Date.now() - Date.parse(season.updated_at) < 7 * 864e5;
  if (season && fresh && !force) {
    const { count } = await db.from("global_episodes")
      .select("id", { count: "exact", head: true }).eq("season_id", season.id);
    if ((count ?? 0) > 0) return readSeason(db, series.id, seasonNumber);
  }

  const d: Json = await tmdb(`/tv/${seriesTmdbId}/season/${seasonNumber}`, { language: LANG });
  const { data: seasonRow, error: e1 } = await db.from("global_seasons").upsert({
    series_id: series.id, season_number: seasonNumber, name: orNull(d.name),
    overview: orNull(d.overview), poster_path: d.poster_path ?? null, air_date: orNull(d.air_date),
    episode_count: (d.episodes ?? []).length, updated_at: new Date().toISOString(),
  }, { onConflict: "series_id,season_number" }).select("id").single();
  if (e1) throw e1;

  const { data: lockedEps } = await db.from("global_episodes")
    .select("episode_number, locked_fields").eq("series_id", series.id).eq("season_number", seasonNumber);
  const skip = new Set((lockedEps ?? []).filter((e) => (e.locked_fields ?? []).length).map((e) => e.episode_number));
  const eps = (d.episodes ?? []).filter((e: Json) => !skip.has(e.episode_number)).map((e: Json) => ({
    series_id: series!.id, season_id: seasonRow.id, season_number: seasonNumber,
    episode_number: e.episode_number, name: orNull(e.name), overview: orNull(e.overview),
    still_path: e.still_path ?? null, air_date: orNull(e.air_date), runtime_min: e.runtime || null,
  }));
  if (eps.length) {
    const { error } = await db.from("global_episodes").upsert(eps, { onConflict: "series_id,season_number,episode_number" });
    if (error) throw error;
  }
  return readSeason(db, series.id, seasonNumber);
}

async function readSeason(db: SupabaseClient, seriesId: string, seasonNumber: number) {
  const { data, error } = await db.from("global_episodes")
    .select("id,episode_number,name,overview,still_path,air_date,runtime_min")
    .eq("series_id", seriesId).eq("season_number", seasonNumber).order("episode_number");
  if (error) throw error;
  return { series_id: seriesId, season: seasonNumber, episodes: data ?? [] };
}
