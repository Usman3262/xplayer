"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";

import { actionGuard, type ActionResult } from "@/lib/auth";
import { dbMessage } from "@/lib/db-errors";
import { createClient } from "@/lib/supabase/server";

/** Publish the current customization (draft tables) to the apps as a new config version. */
export async function publishConfig(notes: string): Promise<ActionResult<{ version: number }>> {
  const guard = await actionGuard("customization.publish");
  if ("error" in guard) return guard.error;
  const parsed = z.string().max(200).safeParse(notes ?? "");
  if (!parsed.success) return { ok: false, error: "Keep the note under 200 characters." };

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("publish_app_config", { p_notes: parsed.data.trim() || undefined });
  if (error) return { ok: false, error: dbMessage(error) };
  revalidatePath("/", "layout");
  return { ok: true, data: { version: Number(data) } };
}

const settingChange = z.object({
  key: z.string().regex(/^[a-z_]+(\.[a-z_]+)+$/),
  value: z.union([z.string().max(1000), z.number(), z.boolean(), z.array(z.string().max(100)).max(50)]),
});

/**
 * Save typed app settings. The DB validates each value against its type/limits
 * (validate_app_setting) and RLS decides who may write which category.
 */
export async function saveSettings(changes: { key: string; value: string | number | boolean | string[] }[]): Promise<ActionResult> {
  const guard = await actionGuard("customization.write");
  if ("error" in guard) return guard.error;
  const parsed = z.array(settingChange).min(1).max(50).safeParse(changes);
  if (!parsed.success) return { ok: false, error: "Invalid settings." };

  const supabase = await createClient();
  const results = await Promise.all(
    parsed.data.map((c) =>
      supabase.from("app_settings").update({ value: c.value }, { count: "exact" }).eq("key", c.key),
    ),
  );
  const failed = results.find((r) => r.error);
  if (failed?.error) return { ok: false, error: dbMessage(failed.error) };
  if (results.some((r) => !r.count)) return { ok: false, error: "Some settings could not be saved (missing permission)." };
  revalidatePath("/customization", "layout");
  return { ok: true };
}
