"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";

import { actionGuard, type ActionResult } from "@/lib/auth";
import { dbMessage } from "@/lib/db-errors";
import type { Json } from "@/lib/supabase/database.types";
import { createClient } from "@/lib/supabase/server";

const policySchema = z.object({
  mode: z.enum(["optional", "required", "disabled"]),
  allow_registration: z.boolean(),
  guest_enabled: z.boolean(),
  max_connections: z.number().int().min(1).max(50),
  connect_timeout_s: z.number().int().min(1).max(60),
});
export type PolicyInput = z.input<typeof policySchema>;

/**
 * Sign-in policy. Consistent combinations are enforced here:
 * required → no guest use; disabled → guest only, no registration.
 */
export async function saveSignInPolicy(input: PolicyInput): Promise<ActionResult> {
  const guard = await actionGuard("customization.write");
  if ("error" in guard) return guard.error;
  const parsed = policySchema.safeParse(input);
  if (!parsed.success) return { ok: false, error: parsed.error.issues[0]?.message ?? "Check the form." };
  const p = parsed.data;
  const guest = p.mode === "required" ? false : p.mode === "disabled" ? true : p.guest_enabled;
  const registration = p.mode === "disabled" ? false : p.allow_registration;
  if (p.mode === "optional" && !guest) {
    return { ok: false, error: "With optional sign-in, guest use must stay on (otherwise choose “Required”)." };
  }

  const values: Record<string, Json> = {
    "auth.mode": p.mode,
    "auth.guest_enabled": guest,
    "auth.allow_registration": registration,
    "providers.max_connections": p.max_connections,
    "providers.connect_timeout_ms": p.connect_timeout_s * 1000,
  };
  const supabase = await createClient();
  const results = await Promise.all(
    Object.entries(values).map(([key, value]) => supabase.from("app_settings").update({ value }).eq("key", key)),
  );
  const failed = results.find((r) => r.error);
  if (failed?.error) return { ok: false, error: dbMessage(failed.error) };
  revalidatePath("/customization", "layout");
  return { ok: true };
}

const panelKey = z.string().regex(/^[a-z0-9_]+$/);

/** Enable/disable a panel type; at least one must stay enabled. */
export async function setPanelEnabled(key: string, enabled: boolean): Promise<ActionResult> {
  const guard = await actionGuard("customization.write");
  if ("error" in guard) return guard.error;
  if (!panelKey.safeParse(key).success) return { ok: false, error: "Invalid panel type." };
  const supabase = await createClient();
  if (!enabled) {
    const { count } = await supabase
      .from("onboarding_panel_types")
      .select("key", { count: "exact", head: true })
      .eq("is_enabled", true)
      .neq("key", key);
    if (!count) return { ok: false, error: "Keep at least one panel type on — users need a way to connect." };
  }
  const { error } = await supabase.from("onboarding_panel_types").update({ is_enabled: enabled }).eq("key", key);
  if (error) return { ok: false, error: dbMessage(error) };
  revalidatePath("/customization", "layout");
  return { ok: true };
}

/** Move a panel type up/down on the "Choose your panel" screen. */
export async function movePanel(key: string, direction: "up" | "down"): Promise<ActionResult> {
  const guard = await actionGuard("customization.write");
  if ("error" in guard) return guard.error;
  if (!panelKey.safeParse(key).success) return { ok: false, error: "Invalid panel type." };
  const supabase = await createClient();
  const { data, error } = await supabase.from("onboarding_panel_types").select("key,sort_order").order("sort_order").order("key");
  if (error || !data) return { ok: false, error: dbMessage(error) };
  const i = data.findIndex((r) => r.key === key);
  const j = direction === "up" ? i - 1 : i + 1;
  if (i < 0 || j < 0 || j >= data.length) return { ok: true };
  // Renumber everything 10, 20, 30… with the two swapped (stable, no ties).
  const order = [...data];
  [order[i], order[j]] = [order[j], order[i]];
  const results = await Promise.all(
    order.map((r, idx) => supabase.from("onboarding_panel_types").update({ sort_order: (idx + 1) * 10 }).eq("key", r.key)),
  );
  const failed = results.find((r) => r.error);
  if (failed?.error) return { ok: false, error: dbMessage(failed.error) };
  revalidatePath("/customization", "layout");
  return { ok: true };
}

const panelSchema = z.object({
  key: panelKey,
  label: z.string().trim().min(2).max(40),
  description: z.string().trim().max(120),
  help_text: z.string().trim().max(300),
  platforms: z.array(z.enum(["android", "ios", "tv"])),
  fields: z
    .array(
      z.object({
        key: z.string().regex(/^[a-z_]+$/),
        label: z.string().trim().min(1).max(40),
        placeholder: z.string().trim().max(80),
        required: z.boolean(),
      }),
    )
    .max(10),
});
export type PanelInput = z.input<typeof panelSchema>;

type StoredField = { key: string; type: string; label: string; placeholder?: string; required?: boolean };

/**
 * Edit labels/help/platforms and field texts. Field keys and types stay as built
 * (the app's provider code reads them), so edits are merged onto existing fields.
 */
export async function updatePanel(input: PanelInput): Promise<ActionResult> {
  const guard = await actionGuard("customization.write");
  if ("error" in guard) return guard.error;
  const parsed = panelSchema.safeParse(input);
  if (!parsed.success) return { ok: false, error: parsed.error.issues[0]?.message ?? "Check the form." };
  const v = parsed.data;

  const supabase = await createClient();
  const { data: row, error: readError } = await supabase
    .from("onboarding_panel_types")
    .select("fields")
    .eq("key", v.key)
    .maybeSingle();
  if (readError || !row) return { ok: false, error: "Panel type not found." };

  const edits = new Map(v.fields.map((f) => [f.key, f]));
  const fields = ((row.fields as StoredField[]) ?? []).map((f) => {
    const e = edits.get(f.key);
    return e ? { ...f, label: e.label, placeholder: e.placeholder || undefined, required: e.required } : f;
  });

  const { error } = await supabase
    .from("onboarding_panel_types")
    .update({
      label: v.label,
      description: v.description || null,
      help_text: v.help_text || null,
      platforms: v.platforms.length === 0 || v.platforms.length === 3 ? null : v.platforms,
      fields,
    })
    .eq("key", v.key);
  if (error) return { ok: false, error: dbMessage(error) };
  revalidatePath("/customization", "layout");
  return { ok: true };
}
