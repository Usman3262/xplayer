"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";

import { actionGuard, type ActionResult } from "@/lib/auth";
import { dbMessage } from "@/lib/db-errors";
import { parseEvents, parseLineup } from "@/lib/sports-parse";
import { createClient } from "@/lib/supabase/server";

const STATUSES = ["scheduled", "live", "halftime", "finished", "postponed", "cancelled", "suspended"] as const;

const matchSchema = z
  .object({
    competition: z.string().trim().max(80),
    home: z.string().trim().min(1, "Enter the home team").max(80),
    away: z.string().trim().min(1, "Enter the away team").max(80),
    kickoff_at: z.string().min(1, "Pick the kickoff time"),
    status: z.enum(STATUSES),
    minute: z.number().int().min(0).max(200).nullable(),
    home_score: z.number().int().min(0).max(99).nullable(),
    away_score: z.number().int().min(0).max(99).nullable(),
    round: z.string().trim().max(60),
    venue: z.string().trim().max(120),
    is_featured: z.boolean(),
    is_hidden: z.boolean(),
    channels: z.string().max(2000),
    home_formation: z.string().trim().max(20),
    away_formation: z.string().trim().max(20),
    home_lineup: z.string().max(4000),
    away_lineup: z.string().max(4000),
    events: z.string().max(6000),
  })
  .refine((v) => v.home.toLowerCase() !== v.away.toLowerCase(), "Home and away must be different teams.")
  .refine((v) => !Number.isNaN(new Date(v.kickoff_at).getTime()), "Invalid kickoff time.");
export type MatchInput = z.input<typeof matchSchema>;

type Db = Awaited<ReturnType<typeof createClient>>;

/** Find by name (case-insensitive) or create. Manually created rows have no external id. */
async function teamId(db: Db, name: string): Promise<string> {
  const { data } = await db.from("sports_teams").select("id").ilike("name", name.replace(/[%_]/g, "\\$&")).limit(1);
  if (data?.[0]) return data[0].id;
  const { data: created, error } = await db.from("sports_teams").insert({ name }).select("id").single();
  if (error) throw error;
  return created.id;
}

async function competitionId(db: Db, name: string): Promise<string | null> {
  if (!name) return null;
  const { data } = await db.from("sports_competitions").select("id").ilike("name", name.replace(/[%_]/g, "\\$&")).limit(1);
  if (data?.[0]) return data[0].id;
  const { data: created, error } = await db.from("sports_competitions").insert({ name }).select("id").single();
  if (error) throw error;
  return created.id;
}

export async function saveMatch(id: string | null, input: MatchInput): Promise<ActionResult> {
  const guard = await actionGuard("sports.write");
  if ("error" in guard) return guard.error;
  if (id && !z.uuid().safeParse(id).success) return { ok: false, error: "Invalid match." };
  const parsed = matchSchema.safeParse(input);
  if (!parsed.success) return { ok: false, error: parsed.error.issues[0]?.message ?? "Check the form." };
  const v = parsed.data;
  const ev = parseEvents(v.events);
  if (ev.errors.length) return { ok: false, error: ev.errors[0] };

  const db = await createClient();
  try {
    const [homeId, awayId, compId] = await Promise.all([teamId(db, v.home), teamId(db, v.away), competitionId(db, v.competition)]);
    const row = {
      competition_id: compId,
      home_team_id: homeId,
      away_team_id: awayId,
      kickoff_at: new Date(v.kickoff_at).toISOString(),
      status: v.status,
      minute: v.status === "live" ? v.minute : null,
      home_score: v.status === "scheduled" ? null : v.home_score,
      away_score: v.status === "scheduled" ? null : v.away_score,
      round: v.round || null,
      venue: v.venue || null,
      is_featured: v.is_featured,
      is_hidden: v.is_hidden,
    };
    let matchId = id;
    if (id) {
      const { error } = await db.from("sports_matches").update(row).eq("id", id);
      if (error) throw error;
    } else {
      const { data, error } = await db.from("sports_matches").insert(row).select("id").single();
      if (error) throw error;
      matchId = data.id;
    }
    const mid = matchId!;

    // Children are replaced as a whole (small lists).
    await Promise.all([
      db.from("sports_match_channels").delete().eq("match_id", mid),
      db.from("sports_lineups").delete().eq("match_id", mid),
      db.from("sports_events").delete().eq("match_id", mid),
    ]);
    const channels = v.channels.split(/[\n,]/).map((c) => c.trim()).filter(Boolean).slice(0, 20);
    const homeLineup = parseLineup(v.home_lineup);
    const awayLineup = parseLineup(v.away_lineup);
    const inserts = [];
    if (channels.length) inserts.push(db.from("sports_match_channels").insert(channels.map((c) => ({ match_id: mid, channel_match: c }))));
    const lineups = [
      { team_id: homeId, formation: v.home_formation || null, players: homeLineup },
      { team_id: awayId, formation: v.away_formation || null, players: awayLineup },
    ].filter((l) => l.players.length || l.formation);
    if (lineups.length) inserts.push(db.from("sports_lineups").insert(lineups.map((l) => ({ ...l, match_id: mid }))));
    if (ev.out.length) {
      inserts.push(
        db.from("sports_events").insert(
          ev.out.map((e) => ({
            match_id: mid,
            team_id: e.side === "home" ? homeId : e.side === "away" ? awayId : null,
            minute: e.minute,
            extra_minute: e.extra_minute,
            type: e.type,
            player: e.player,
            assist: e.assist,
          })),
        ),
      );
    }
    const results = await Promise.all(inserts);
    const failed = results.find((r) => r.error);
    if (failed?.error) throw failed.error;
  } catch (e) {
    return { ok: false, error: dbMessage(e as { code?: string; message?: string }) };
  }
  revalidatePath("/sports");
  return { ok: true };
}

export async function deleteMatch(id: string): Promise<ActionResult> {
  const guard = await actionGuard("sports.write");
  if ("error" in guard) return guard.error;
  if (!z.uuid().safeParse(id).success) return { ok: false, error: "Invalid match." };
  const { error } = await (await createClient()).from("sports_matches").delete().eq("id", id);
  if (error) return { ok: false, error: dbMessage(error) };
  revalidatePath("/sports");
  return { ok: true };
}

export async function setCompetitionFlag(id: string, field: "is_enabled" | "is_featured", value: boolean): Promise<ActionResult> {
  const guard = await actionGuard("sports.write");
  if ("error" in guard) return guard.error;
  if (!z.uuid().safeParse(id).success) return { ok: false, error: "Invalid competition." };
  const patch = field === "is_enabled" ? { is_enabled: value } : { is_featured: value };
  const { error } = await (await createClient()).from("sports_competitions").update(patch).eq("id", id);
  if (error) return { ok: false, error: dbMessage(error) };
  revalidatePath("/sports");
  return { ok: true };
}
