"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";

import { actionGuard, type ActionResult } from "@/lib/auth";
import { dbMessage } from "@/lib/db-errors";
import { createClient } from "@/lib/supabase/server";

const flagKey = z.string().regex(/^[a-z_]+$/);
const version = z
  .string()
  .trim()
  .regex(/^\d+(\.\d+){0,2}$/, "Use a version like 1.4 or 1.4.2")
  .or(z.literal(""))
  .transform((v) => v || null);
const dateTime = z
  .string()
  .trim()
  .or(z.literal(""))
  .transform((v) => (v ? new Date(v) : null))
  .refine((d) => d === null || !Number.isNaN(d.getTime()), "Invalid date");

/** Quick on/off. RLS checks customization.write in the DB as well. */
export async function setFlagEnabled(key: string, enabled: boolean): Promise<ActionResult> {
  const guard = await actionGuard("customization.write");
  if ("error" in guard) return guard.error;
  if (!flagKey.safeParse(key).success) return { ok: false, error: "Invalid flag." };

  const supabase = await createClient();
  const { error, count } = await supabase
    .from("feature_flags")
    .update({ enabled, updated_by: guard.admin.userId }, { count: "exact" })
    .eq("key", key);
  if (error) return { ok: false, error: dbMessage(error) };
  if (!count) return { ok: false, error: "Flag not found." };
  revalidatePath("/customization", "layout");
  return { ok: true };
}

const editSchema = z
  .object({
    key: flagKey,
    name: z.string().trim().min(2).max(60),
    description: z.string().trim().min(2).max(200),
    platforms: z.array(z.enum(["android", "ios", "tv"])),
    min_app_version: version,
    max_app_version: version,
    starts_at: dateTime,
    ends_at: dateTime,
  })
  .refine((v) => !v.starts_at || !v.ends_at || v.ends_at > v.starts_at, {
    message: "End must be after start.",
    path: ["ends_at"],
  });

export type FlagEdit = z.input<typeof editSchema>;

export async function updateFlag(input: FlagEdit): Promise<ActionResult> {
  const guard = await actionGuard("customization.write");
  if ("error" in guard) return guard.error;
  const parsed = editSchema.safeParse(input);
  if (!parsed.success) return { ok: false, error: parsed.error.issues[0]?.message ?? "Check the form." };
  const v = parsed.data;

  const supabase = await createClient();
  const { error, count } = await supabase
    .from("feature_flags")
    .update(
      {
        name: v.name,
        description: v.description,
        // All three ticked (or none) = every platform → store null.
        platforms: v.platforms.length === 0 || v.platforms.length === 3 ? null : v.platforms,
        min_app_version: v.min_app_version,
        max_app_version: v.max_app_version,
        starts_at: v.starts_at?.toISOString() ?? null,
        ends_at: v.ends_at?.toISOString() ?? null,
        updated_by: guard.admin.userId,
      },
      { count: "exact" },
    )
    .eq("key", v.key);
  if (error) return { ok: false, error: dbMessage(error) };
  if (!count) return { ok: false, error: "Flag not found." };
  revalidatePath("/customization", "layout");
  return { ok: true };
}
