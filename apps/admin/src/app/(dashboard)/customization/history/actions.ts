"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";

import { actionGuard, type ActionResult } from "@/lib/auth";
import { dbMessage } from "@/lib/db-errors";
import { createClient } from "@/lib/supabase/server";

/** Emergency rollback: publish an older version's snapshot again as a new version. */
export async function rollbackTo(version: number): Promise<ActionResult<{ version: number }>> {
  const guard = await actionGuard("customization.publish");
  if ("error" in guard) return guard.error;
  if (!z.number().int().positive().safeParse(version).success) return { ok: false, error: "Invalid version." };
  const { data, error } = await (await createClient()).rpc("admin_republish_version", { p_version: version });
  if (error) return { ok: false, error: dbMessage(error) };
  revalidatePath("/", "layout");
  return { ok: true, data: { version: Number(data) } };
}
