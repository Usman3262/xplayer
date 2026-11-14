"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";

import { actionGuard, type ActionResult } from "@/lib/auth";
import { dbMessage } from "@/lib/db-errors";
import { createClient } from "@/lib/supabase/server";

const uuid = z.uuid();
const done = () => revalidatePath("/customization", "layout");

const listSchema = z.object({
  title: z.string().trim().min(1, "Give the list a title").max(80),
  content_kind: z.enum(["mixed", "movie", "series"]),
  source: z.enum(["provider_rating", "provider_added", "manual", "watch_stats"]),
  days: z.number().int().min(1).max(365).nullable(),
  min_rating: z.number().min(0).max(10).nullable(),
  country: z.string().trim().toUpperCase().regex(/^([A-Z]{2})?$/, "Country is a 2-letter code like PK").max(2),
  is_enabled: z.boolean(),
});
export type Top10ListInput = z.input<typeof listSchema>;

const itemSchema = z
  .object({
    item_kind: z.enum(["movie", "series"]),
    tmdb_id: z.number().int().positive().nullable(),
    match_title: z.string().trim().max(120),
    panel_item_id: z.string().trim().max(60),
    panel_key: z.string().trim().regex(/^[a-z0-9_]*$/).max(30),
  })
  .refine((v) => !!(v.tmdb_id || v.match_title || v.panel_item_id), "Each ranked title needs a TMDB id, a title or a panel id.");
export type Top10ItemInput = z.input<typeof itemSchema>;

export async function saveTop10List(id: string | null, input: Top10ListInput, items: Top10ItemInput[]): Promise<ActionResult> {
  const guard = await actionGuard("customization.write");
  if ("error" in guard) return guard.error;
  if (id && !uuid.safeParse(id).success) return { ok: false, error: "Invalid list." };
  const parsed = listSchema.safeParse(input);
  if (!parsed.success) return { ok: false, error: parsed.error.issues[0]?.message ?? "Check the form." };
  const v = parsed.data;
  const parsedItems = z.array(itemSchema).max(10).safeParse(v.source === "manual" ? items : []);
  if (!parsedItems.success) return { ok: false, error: parsedItems.error.issues[0]?.message ?? "Check the ranked titles." };

  const params: Record<string, number> = {};
  if (v.source === "provider_rating" || v.source === "provider_added") {
    if (v.days) params.days = v.days;
    if (v.source === "provider_rating" && v.min_rating !== null) params.min_rating = v.min_rating;
  }
  const row = {
    title: v.title,
    content_kind: v.content_kind,
    source: v.source,
    params,
    country: v.country || null,
    is_enabled: v.is_enabled,
    updated_by: guard.admin.userId,
  };

  const supabase = await createClient();
  let listId = id;
  if (id) {
    const { error, count } = await supabase.from("top10_lists").update(row, { count: "exact" }).eq("id", id);
    if (error) return { ok: false, error: dbMessage(error) };
    if (!count) return { ok: false, error: "List not found." };
  } else {
    const { data, error } = await supabase.from("top10_lists").insert(row).select("id").single();
    if (error) return { ok: false, error: dbMessage(error) };
    listId = data.id;
  }

  // Ranked picks only matter for manual lists; others are computed on the device.
  const { error: delError } = await supabase.from("top10_items").delete().eq("list_id", listId!);
  if (delError) return { ok: false, error: dbMessage(delError) };
  if (parsedItems.data.length) {
    const { error } = await supabase.from("top10_items").insert(
      parsedItems.data.map((it, i) => ({
        list_id: listId!,
        rank: i + 1,
        item_kind: it.item_kind,
        tmdb_id: it.tmdb_id,
        match_title: it.match_title || null,
        panel_item_id: it.panel_item_id || null,
        panel_key: it.panel_item_id && it.panel_key ? it.panel_key : null,
      })),
    );
    if (error) return { ok: false, error: dbMessage(error) };
  }
  done();
  return { ok: true };
}

export async function deleteTop10List(id: string): Promise<ActionResult> {
  const guard = await actionGuard("customization.write");
  if ("error" in guard) return guard.error;
  if (!uuid.safeParse(id).success) return { ok: false, error: "Invalid list." };
  const { error } = await (await createClient()).from("top10_lists").delete().eq("id", id);
  if (error) return { ok: false, error: dbMessage(error) };
  done();
  return { ok: true };
}
