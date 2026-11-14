/** Pure parsers for the Sports match dialog (unit-tested in scripts/test-sports-parse.ts). */

export const EVENT_TYPES = ["goal", "own_goal", "penalty_goal", "penalty_miss", "yellow", "red", "substitution", "var", "other"] as const;

/** "9 Mohamed Salah FW" per line; a line "subs"/"bench" starts the bench. */
export function parseLineup(text: string) {
  const players: { name: string; number?: number; position?: string; starter: boolean }[] = [];
  let starter = true;
  for (const raw of text.split("\n")) {
    const line = raw.trim();
    if (!line) continue;
    if (/^(subs|bench|substitutes)\b/i.test(line)) {
      starter = false;
      continue;
    }
    const m = line.match(/^(\d{1,2})?\s*(.+?)(?:\s+(GK|DF|MF|FW|D|M|F|G))?$/i);
    if (!m) continue;
    players.push({
      name: m[2].trim(),
      ...(m[1] ? { number: Number(m[1]) } : {}),
      ...(m[3] ? { position: m[3].toUpperCase() } : {}),
      starter,
    });
  }
  return players;
}

/** "45+2 goal home Salah (Nunez)" per line. */
export function parseEvents(text: string) {
  const out: { minute: number; extra_minute: number | null; type: (typeof EVENT_TYPES)[number]; side: "home" | "away" | null; player: string | null; assist: string | null }[] = [];
  const errors: string[] = [];
  for (const [i, raw] of text.split("\n").entries()) {
    const line = raw.trim();
    if (!line) continue;
    const m = line.match(/^(\d{1,3})(?:\+(\d{1,2}))?'?\s+([a-z_]+)(?:\s+(home|away))?(?:\s+([^()]+?))?(?:\s*\(([^)]+)\))?$/i);
    const type = m?.[3]?.toLowerCase();
    if (!m || !EVENT_TYPES.includes(type as never)) {
      errors.push(`Event line ${i + 1}: use “minute type home|away player”, e.g. “45+2 goal home Salah”.`);
      continue;
    }
    out.push({
      minute: Number(m[1]),
      extra_minute: m[2] ? Number(m[2]) : null,
      type: type as (typeof EVENT_TYPES)[number],
      side: (m[4]?.toLowerCase() as "home" | "away") ?? null,
      player: m[5]?.trim() || null,
      assist: m[6]?.trim() || null,
    });
  }
  return { out, errors };
}

