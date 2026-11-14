"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";

import { actionGuard, type ActionResult } from "@/lib/auth";
import { dbMessage } from "@/lib/db-errors";
import { KINDS, LAYOUTS, SECTION_TYPES, SOURCE_PARAMS, SOURCES } from "@/lib/home-sections";
import { createClient } from "@/lib/supabase/server";

const T = "home_sections";
const uuid = z.uuid();
const enumOf = <T extends Record<string, unknown>>(o: T) => z.enum(Object.keys(o) as [string, ...string[]]);

const sectionSchema = z
  .object({
    title: z.string().trim().min(1, "Give the section a title").max(80),
    subtitle: z.string().trim().max(160),
    section_type: enumOf(SECTION_TYPES),
    content_kind: enumOf(KINDS),
    source: enumOf(SOURCES),
    layout: enumOf(LAYOUTS),
    item_limit: z.number().int().min(1).max(100),
    params: z.object({
      days: z.number().int().min(1).max(365).optional(),
      match: z.string().trim().max(80).optional(),
      min_rating: z.number().min(0).max(10).optional(),
    }),
    platforms: z.array(z.enum(["android", "ios", "tv"])),
    countries: z.array(z.string().regex(/^[A-Z]{2}$/, "Countries are 2-letter codes like PK, AE")).max(50),
    requires_login: z.boolean(),
    starts_at: z.string(),
    ends_at: z.string(),
    top10_list_id: z.uuid().nullable(),
  })
  .superRefine((v, ctx) => {
    if (v.section_type === "top10" && !v.top10_list_id) ctx.addIssue({ code: "custom", message: "Pick which Top 10 list this section shows." });
    const def = SECTION_TYPES[v.section_type];
    if (!def.sources.includes(v.source as never)) ctx.addIssue({ code: "custom", message: `“${SOURCES[v.source as keyof typeof SOURCES].label}” doesn't fit a ${def.label} section.` });
    if (!def.layouts.includes(v.layout as never)) ctx.addIssue({ code: "custom", message: `That layout doesn't fit a ${def.label} section.` });
    if (!def.kinds.includes(v.content_kind as never)) ctx.addIssue({ code: "custom", message: `That content type doesn't fit a ${def.label} section.` });
    if (v.source === "provider_category" && !v.params.match) ctx.addIssue({ code: "custom", message: "Enter the category name to match." });
    const s = v.starts_at ? new Date(v.starts_at) : null;
    const e = v.ends_at ? new Date(v.ends_at) : null;
    if ((s && Number.isNaN(s.getTime())) || (e && Number.isNaN(e.getTime()))) ctx.addIssue({ code: "custom", message: "Invalid date." });
    if (s && e && e <= s) ctx.addIssue({ code: "custom", message: "End must be after start." });
  });

export type SectionInput = z.input<typeof sectionSchema>;

function toRow(v: z.output<typeof sectionSchema>) {
  const allowed = SOURCE_PARAMS[v.source as keyof typeof SOURCE_PARAMS] ?? [];
  const params = Object.fromEntries(Object.entries(v.params).filter(([k, val]) => allowed.includes(k as never) && val !== undefined && val !== ""));
  return {
    title: v.title,
    subtitle: v.subtitle || null,
    section_type: v.section_type,
    content_kind: v.content_kind,
    source: v.source,
    layout: v.layout,
    item_limit: v.item_limit,
    params,
    platforms: v.platforms.length === 0 || v.platforms.length === 3 ? null : v.platforms,
    countries: v.countries.length ? v.countries : null,
    requires_login: v.requires_login,
    starts_at: v.starts_at ? new Date(v.starts_at).toISOString() : null,
    ends_at: v.ends_at ? new Date(v.ends_at).toISOString() : null,
    top10_list_id: v.section_type === "top10" ? v.top10_list_id : null,
  };
}

const done = () => revalidatePath("/customization", "layout");

export async function createSection(input: SectionInput): Promise<ActionResult<{ id: string }>> {
  const guard = await actionGuard("customization.write");
  if ("error" in guard) return guard.error;
  const parsed = sectionSchema.safeParse(input);
  if (!parsed.success) return { ok: false, error: parsed.error.issues[0]?.message ?? "Check the form." };
  const supabase = await createClient();
  const { data: last } = await supabase.from(T).select("sort_order").order("sort_order", { ascending: false }).limit(1);
  const { data, error } = await supabase
    .from(T)
    .insert({ ...toRow(parsed.data), sort_order: (last?.[0]?.sort_order ?? 0) + 10, updated_by: guard.admin.userId })
    .select("id")
    .single();
  if (error) return { ok: false, error: dbMessage(error) };
  done();
  return { ok: true, data: { id: data.id } };
}

export async function updateSection(id: string, input: SectionInput): Promise<ActionResult> {
  const guard = await actionGuard("customization.write");
  if ("error" in guard) return guard.error;
  if (!uuid.safeParse(id).success) return { ok: false, error: "Invalid section." };
  const parsed = sectionSchema.safeParse(input);
  if (!parsed.success) return { ok: false, error: parsed.error.issues[0]?.message ?? "Check the form." };
  const supabase = await createClient();
  const { error, count } = await supabase.from(T).update({ ...toRow(parsed.data), updated_by: guard.admin.userId }, { count: "exact" }).eq("id", id);
  if (error) return { ok: false, error: dbMessage(error) };
  if (!count) return { ok: false, error: "Section not found." };
  done();
  return { ok: true };
}

export async function setSectionEnabled(id: string, enabled: boolean): Promise<ActionResult> {
  const guard = await actionGuard("customization.write");
  if ("error" in guard) return guard.error;
  if (!uuid.safeParse(id).success) return { ok: false, error: "Invalid section." };
  const supabase = await createClient();
  const { error } = await supabase.from(T).update({ is_enabled: enabled }).eq("id", id);
  if (error) return { ok: false, error: dbMessage(error) };
  done();
  return { ok: true };
}

export async function moveSection(id: string, direction: "up" | "down" | "top" | "bottom"): Promise<ActionResult> {
  const guard = await actionGuard("customization.write");
  if ("error" in guard) return guard.error;
  if (!uuid.safeParse(id).success) return { ok: false, error: "Invalid section." };
  const supabase = await createClient();
  const { data, error } = await supabase.from(T).select("id").order("sort_order").order("created_at");
  if (error || !data) return { ok: false, error: dbMessage(error) };
  const ids = data.map((r) => r.id);
  const i = ids.indexOf(id);
  if (i < 0) return { ok: false, error: "Section not found." };
  ids.splice(i, 1);
  const j = direction === "up" ? Math.max(0, i - 1) : direction === "down" ? Math.min(ids.length, i + 1) : direction === "top" ? 0 : ids.length;
  ids.splice(j, 0, id);
  // Only rows whose position changed are written.
  const results = await Promise.all(
    ids.map((rid, idx) => (data[idx]?.id === rid ? null : supabase.from(T).update({ sort_order: (idx + 1) * 10 }).eq("id", rid))).filter(Boolean),
  );
  const failed = results.find((r) => r?.error);
  if (failed?.error) return { ok: false, error: dbMessage(failed.error) };
  done();
  return { ok: true };
}

export async function deleteSection(id: string): Promise<ActionResult> {
  const guard = await actionGuard("customization.write");
  if ("error" in guard) return guard.error;
  if (!uuid.safeParse(id).success) return { ok: false, error: "Invalid section." };
  const supabase = await createClient();
  const { error } = await supabase.from(T).delete().eq("id", id);
  if (error) return { ok: false, error: dbMessage(error) };
  done();
  return { ok: true };
}

const itemSchema = z
  .object({
    item_kind: z.enum(["movie", "series", "live", "link"]),
    tmdb_id: z.number().int().positive().nullable(),
    match_title: z.string().trim().max(120),
    panel_item_id: z.string().trim().max(60),
    panel_key: z.string().trim().regex(/^[a-z0-9_]*$/, "Panel key: lowercase letters, digits, _").max(30),
    title: z.string().trim().max(120),
    image_url: z.string().trim().max(500).refine((v) => v === "" || v.startsWith("https://"), "Images must be https URLs"),
    deep_link: z.string().trim().max(300),
  })
  .refine((v) => (v.item_kind === "link" ? !!v.deep_link : !!(v.tmdb_id || v.match_title || v.panel_item_id)), {
    message: "Each pick needs a TMDB id, a title to match or a panel id (links need a link).",
  });
export type ItemInput = z.input<typeof itemSchema>;

/** Replace a section's manual picks (in order). */
export async function setSectionItems(id: string, items: ItemInput[]): Promise<ActionResult> {
  const guard = await actionGuard("customization.write");
  if ("error" in guard) return guard.error;
  if (!uuid.safeParse(id).success) return { ok: false, error: "Invalid section." };
  const parsed = z.array(itemSchema).max(100).safeParse(items);
  if (!parsed.success) return { ok: false, error: parsed.error.issues[0]?.message ?? "Check the picks." };
  const supabase = await createClient();
  const { error: delError } = await supabase.from("home_section_items").delete().eq("section_id", id);
  if (delError) return { ok: false, error: dbMessage(delError) };
  if (parsed.data.length) {
    const { error } = await supabase.from("home_section_items").insert(
      parsed.data.map((it, i) => ({
        section_id: id,
        sort_order: (i + 1) * 10,
        item_kind: it.item_kind,
        tmdb_id: it.tmdb_id,
        match_title: it.match_title || null,
        panel_item_id: it.panel_item_id || null,
        panel_key: it.panel_item_id && it.panel_key ? it.panel_key : null,
        title: it.title || null,
        image_url: it.image_url || null,
        deep_link: it.deep_link || null,
      })),
    );
    if (error) return { ok: false, error: dbMessage(error) };
  }
  done();
  return { ok: true };
}
