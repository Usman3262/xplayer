"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";

import { actionGuard, type ActionResult } from "@/lib/auth";
import { dbMessage } from "@/lib/db-errors";
import { createClient } from "@/lib/supabase/server";
import { HEX, THEME_TOKENS } from "@/lib/theme-tokens";

const tokensSchema = z.object(
  Object.fromEntries(THEME_TOKENS.map((t) => [t.key, z.string().regex(HEX, `${t.label}: use #RRGGBB`)])) as Record<
    (typeof THEME_TOKENS)[number]["key"],
    z.ZodString
  >,
);

/** Save the active theme's colours (draft until published). */
export async function saveTheme(tokens: Record<string, string>): Promise<ActionResult> {
  const guard = await actionGuard("customization.write");
  if ("error" in guard) return guard.error;
  const parsed = tokensSchema.safeParse(tokens);
  if (!parsed.success) return { ok: false, error: parsed.error.issues[0]?.message ?? "Invalid colour." };
  const clean = Object.fromEntries(Object.entries(parsed.data).map(([k, v]) => [k, v.toUpperCase()]));

  const supabase = await createClient();
  const { error, count } = await supabase
    .from("app_themes")
    .update({ tokens: clean, updated_by: guard.admin.userId }, { count: "exact" })
    .eq("is_active", true);
  if (error) return { ok: false, error: dbMessage(error) };
  if (!count) return { ok: false, error: "No active theme found." };
  revalidatePath("/customization", "layout");
  return { ok: true };
}

const brandingSchema = z.object({
  display_name: z.string().trim().max(40),
  tagline: z.string().trim().max(80),
  logo_url: z.string().trim().max(500).refine((v) => v === "" || v.startsWith("https://"), "Logo must be an https URL"),
  splash_url: z.string().trim().max(500).refine((v) => v === "" || v.startsWith("https://"), "Splash must be an https URL"),
});

export type BrandingInput = z.input<typeof brandingSchema>;

/** Save branding settings (each is a typed app_settings row, validated by the DB too). */
export async function saveBranding(input: BrandingInput): Promise<ActionResult> {
  const guard = await actionGuard("customization.write");
  if ("error" in guard) return guard.error;
  const parsed = brandingSchema.safeParse(input);
  if (!parsed.success) return { ok: false, error: parsed.error.issues[0]?.message ?? "Check the form." };

  const supabase = await createClient();
  const results = await Promise.all(
    Object.entries(parsed.data).map(([field, value]) =>
      supabase.from("app_settings").update({ value }).eq("key", `branding.${field}`),
    ),
  );
  const failed = results.find((r) => r.error);
  if (failed?.error) return { ok: false, error: dbMessage(failed.error) };
  revalidatePath("/customization", "layout");
  return { ok: true };
}
