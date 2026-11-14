"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";

import { actionGuard, type ActionResult } from "@/lib/auth";
import { dbMessage } from "@/lib/db-errors";
import { createClient } from "@/lib/supabase/server";
import { targetingSchema, targetingToRow } from "@/lib/targeting";

const T = "banners";
const https = (label: string) =>
  z.string().trim().max(500).refine((v) => v === "" || v.startsWith("https://"), `${label} must be an https URL`);

const bannerSchema = z
  .object({
    title: z.string().trim().min(1, "Give the banner a title").max(100),
    subtitle: z.string().trim().max(200),
    image_url: https("Phone image").refine((v) => v !== "", "Upload a phone image"),
    image_url_tv: https("TV image"),
    cta_label: z.string().trim().max(30),
    action_type: z.enum(["none", "content", "category", "screen", "url"]),
    action_value: z.string().trim().max(300),
    item_kind: z.enum(["movie", "series", "live"]),
    tmdb_id: z.number().int().positive().nullable(),
    panel_item_id: z.string().trim().max(60),
    panel_key: z.string().trim().regex(/^[a-z0-9_]*$/).max(30),
    targeting: targetingSchema,
  })
  .superRefine((v, ctx) => {
    if (v.action_type === "content" && !v.tmdb_id && !v.panel_item_id) ctx.addIssue({ code: "custom", message: "“Open a title” needs a TMDB id or panel id." });
    if (v.action_type === "url" && !v.action_value.startsWith("https://")) ctx.addIssue({ code: "custom", message: "The link must start with https://" });
    if ((v.action_type === "category" || v.action_type === "screen") && !v.action_value) ctx.addIssue({ code: "custom", message: "Enter the category or screen to open." });
  });

export type BannerInput = z.input<typeof bannerSchema>;

function toRow(v: z.output<typeof bannerSchema>) {
  const content = v.action_type === "content";
  return {
    title: v.title,
    subtitle: v.subtitle || null,
    image_url: v.image_url,
    image_url_tv: v.image_url_tv || null,
    cta_label: v.cta_label || null,
    action_type: v.action_type,
    action_value: content || v.action_type === "none" ? null : v.action_value,
    item_kind: content ? v.item_kind : null,
    tmdb_id: content ? v.tmdb_id : null,
    panel_item_id: content && v.panel_item_id ? v.panel_item_id : null,
    panel_key: content && v.panel_item_id && v.panel_key ? v.panel_key : null,
    ...targetingToRow(v.targeting),
  };
}

const done = () => revalidatePath("/customization", "layout");
const uuid = z.uuid();

export async function saveBanner(id: string | null, input: BannerInput): Promise<ActionResult> {
  const guard = await actionGuard("customization.write");
  if ("error" in guard) return guard.error;
  if (id && !uuid.safeParse(id).success) return { ok: false, error: "Invalid banner." };
  const parsed = bannerSchema.safeParse(input);
  if (!parsed.success) return { ok: false, error: parsed.error.issues[0]?.message ?? "Check the form." };
  const supabase = await createClient();
  const row = { ...toRow(parsed.data), updated_by: guard.admin.userId };
  if (id) {
    const { error, count } = await supabase.from(T).update(row, { count: "exact" }).eq("id", id);
    if (error) return { ok: false, error: dbMessage(error) };
    if (!count) return { ok: false, error: "Banner not found." };
  } else {
    const { data: last } = await supabase.from(T).select("sort_order").order("sort_order", { ascending: false }).limit(1);
    const { error } = await supabase.from(T).insert({ ...row, sort_order: (last?.[0]?.sort_order ?? 0) + 10 });
    if (error) return { ok: false, error: dbMessage(error) };
  }
  done();
  return { ok: true };
}

export async function setBannerEnabled(id: string, enabled: boolean): Promise<ActionResult> {
  const guard = await actionGuard("customization.write");
  if ("error" in guard) return guard.error;
  if (!uuid.safeParse(id).success) return { ok: false, error: "Invalid banner." };
  const { error } = await (await createClient()).from(T).update({ is_enabled: enabled }).eq("id", id);
  if (error) return { ok: false, error: dbMessage(error) };
  done();
  return { ok: true };
}

export async function moveBanner(id: string, direction: "up" | "down"): Promise<ActionResult> {
  const guard = await actionGuard("customization.write");
  if ("error" in guard) return guard.error;
  if (!uuid.safeParse(id).success) return { ok: false, error: "Invalid banner." };
  const supabase = await createClient();
  const { data, error } = await supabase.from(T).select("id").order("sort_order").order("created_at");
  if (error || !data) return { ok: false, error: dbMessage(error) };
  const ids = data.map((r) => r.id);
  const i = ids.indexOf(id);
  const j = direction === "up" ? i - 1 : i + 1;
  if (i < 0 || j < 0 || j >= ids.length) return { ok: true };
  [ids[i], ids[j]] = [ids[j], ids[i]];
  const results = await Promise.all(ids.map((rid, idx) => supabase.from(T).update({ sort_order: (idx + 1) * 10 }).eq("id", rid)));
  const failed = results.find((r) => r.error);
  if (failed?.error) return { ok: false, error: dbMessage(failed.error) };
  done();
  return { ok: true };
}

export async function deleteBanner(id: string): Promise<ActionResult> {
  const guard = await actionGuard("customization.write");
  if ("error" in guard) return guard.error;
  if (!uuid.safeParse(id).success) return { ok: false, error: "Invalid banner." };
  const { error } = await (await createClient()).from(T).delete().eq("id", id);
  if (error) return { ok: false, error: dbMessage(error) };
  done();
  return { ok: true };
}
