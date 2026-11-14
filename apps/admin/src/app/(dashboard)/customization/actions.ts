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
