import { z } from "zod";

/** Server-side schema for TargetingFields values (+ DB-ready conversion). */
export const targetingSchema = z
  .object({
    platforms: z.array(z.enum(["android", "ios", "tv"])),
    countries: z.array(z.string().regex(/^[A-Z]{2}$/, "Countries are 2-letter codes like PK, AE")).max(50),
    requires_login: z.boolean(),
    starts_at: z.string(),
    ends_at: z.string(),
  })
  .superRefine((v, ctx) => {
    const s = v.starts_at ? new Date(v.starts_at) : null;
    const e = v.ends_at ? new Date(v.ends_at) : null;
    if ((s && Number.isNaN(s.getTime())) || (e && Number.isNaN(e.getTime()))) ctx.addIssue({ code: "custom", message: "Invalid date." });
    if (s && e && e <= s) ctx.addIssue({ code: "custom", message: "“Show until” must be after “Show from”." });
  });

export function targetingToRow(t: z.output<typeof targetingSchema>) {
  return {
    platforms: t.platforms.length === 0 || t.platforms.length === 3 ? null : t.platforms,
    countries: t.countries.length ? t.countries : null,
    requires_login: t.requires_login,
    starts_at: t.starts_at ? new Date(t.starts_at).toISOString() : null,
    ends_at: t.ends_at ? new Date(t.ends_at).toISOString() : null,
  };
}
