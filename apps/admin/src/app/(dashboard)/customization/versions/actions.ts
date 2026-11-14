"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";

import { actionGuard, type ActionResult } from "@/lib/auth";
import { dbMessage } from "@/lib/db-errors";
import { createClient } from "@/lib/supabase/server";

const ver = z
  .string()
  .trim()
  .regex(/^\d+(\.\d+){0,2}$/, "Use a version like 1.4 or 1.4.2")
  .or(z.literal(""));

function cmp(a: string, b: string): number {
  const pa = a.split(".").map(Number);
  const pb = b.split(".").map(Number);
  for (let i = 0; i < 3; i++) {
    const d = (pa[i] ?? 0) - (pb[i] ?? 0);
    if (d) return Math.sign(d);
  }
  return 0;
}

const versionSchema = z
  .object({
    platform: z.enum(["android", "ios", "tv"]),
    min_version: ver,
    recommended_version: ver,
    latest_version: ver,
    update_url: z
      .string()
      .trim()
      .max(500)
      .refine((v) => v === "" || v.startsWith("https://"), "Update link must start with https://"),
    release_notes: z.string().trim().max(1000),
  })
  .refine((v) => !v.recommended_version || !v.min_version || cmp(v.recommended_version, v.min_version) >= 0, {
    message: "Recommended version can't be lower than the minimum.",
  })
  .refine((v) => !v.latest_version || !v.recommended_version || cmp(v.latest_version, v.recommended_version) >= 0, {
    message: "Latest version can't be lower than the recommended one.",
  });

export type VersionInput = z.input<typeof versionSchema>;

export async function saveAppVersion(input: VersionInput): Promise<ActionResult> {
  const guard = await actionGuard("customization.write");
  if ("error" in guard) return guard.error;
  const parsed = versionSchema.safeParse(input);
  if (!parsed.success) return { ok: false, error: parsed.error.issues[0]?.message ?? "Check the form." };
  const v = parsed.data;

  const supabase = await createClient();
  const { error, count } = await supabase
    .from("app_versions")
    .update(
      {
        min_version: v.min_version || "0.0.0",
        recommended_version: v.recommended_version || null,
        latest_version: v.latest_version || null,
        update_url: v.update_url || null,
        release_notes: v.release_notes || null,
        updated_by: guard.admin.userId,
      },
      { count: "exact" },
    )
    .eq("platform", v.platform);
  if (error) return { ok: false, error: dbMessage(error) };
  if (!count) return { ok: false, error: "Platform not found." };
  revalidatePath("/customization", "layout");
  return { ok: true };
}

const maintenanceSchema = z
  .object({
    title: z.string().trim().min(2).max(80),
    message: z.string().trim().min(2).max(500),
    platforms: z.array(z.enum(["android", "ios", "tv"])),
    starts_at: z.string().min(1, "Pick a start time"),
    ends_at: z.string().min(1, "Pick an end time"),
  })
  .transform((v) => ({ ...v, start: new Date(v.starts_at), end: new Date(v.ends_at) }))
  .refine((v) => !Number.isNaN(v.start.getTime()) && !Number.isNaN(v.end.getTime()), "Invalid date")
  .refine((v) => v.end > v.start, "End must be after start.");

export type MaintenanceInput = z.input<typeof maintenanceSchema>;

export async function createMaintenance(input: MaintenanceInput): Promise<ActionResult> {
  const guard = await actionGuard("customization.write");
  if ("error" in guard) return guard.error;
  const parsed = maintenanceSchema.safeParse(input);
  if (!parsed.success) return { ok: false, error: parsed.error.issues[0]?.message ?? "Check the form." };
  const v = parsed.data;

  const supabase = await createClient();
  const { error } = await supabase.from("maintenance_windows").insert({
    title: v.title,
    message: v.message,
    platforms: v.platforms.length === 0 || v.platforms.length === 3 ? null : v.platforms,
    starts_at: v.start.toISOString(),
    ends_at: v.end.toISOString(),
    created_by: guard.admin.userId,
  });
  if (error) return { ok: false, error: dbMessage(error) };
  revalidatePath("/customization", "layout");
  return { ok: true };
}

export async function setMaintenanceActive(id: string, active: boolean): Promise<ActionResult> {
  const guard = await actionGuard("customization.write");
  if ("error" in guard) return guard.error;
  if (!z.uuid().safeParse(id).success) return { ok: false, error: "Invalid request." };
  const supabase = await createClient();
  const { error } = await supabase.from("maintenance_windows").update({ is_active: active }).eq("id", id);
  if (error) return { ok: false, error: dbMessage(error) };
  revalidatePath("/customization", "layout");
  return { ok: true };
}

export async function deleteMaintenance(id: string): Promise<ActionResult> {
  const guard = await actionGuard("customization.write");
  if ("error" in guard) return guard.error;
  if (!z.uuid().safeParse(id).success) return { ok: false, error: "Invalid request." };
  const supabase = await createClient();
  const { error } = await supabase.from("maintenance_windows").delete().eq("id", id);
  if (error) return { ok: false, error: dbMessage(error) };
  revalidatePath("/customization", "layout");
  return { ok: true };
}
