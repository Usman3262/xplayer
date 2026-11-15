"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";

import { actionGuard, type ActionResult } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";

const input = z.object({
  userId: z.uuid(),
  status: z.enum(["active", "suspended", "banned"]),
  reason: z.string().trim().max(500).optional(),
});

/**
 * Suspend / ban / re-activate an app user. The DB function re-checks
 * users.write, refuses yourself and admin accounts, blocks sign-in in Supabase
 * Auth and writes the audit row (with the reason).
 */
export async function setUserStatus(raw: { userId: string; status: string; reason?: string }): Promise<ActionResult> {
  const guard = await actionGuard("users.write");
  if ("error" in guard) return guard.error;
  const parsed = input.safeParse(raw);
  if (!parsed.success) return { ok: false, error: "Invalid request." };

  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_set_user_status", {
    p_user: parsed.data.userId,
    p_status: parsed.data.status,
    p_reason: parsed.data.reason || undefined,
  });
  if (error) {
    if (error.code === "42501") {
      return { ok: false, error: error.message.includes("Admins page") ? "Admin accounts are managed on the Admins page." : "You don't have permission for this." };
    }
    if (error.code === "P0002") return { ok: false, error: "This user no longer exists." };
    return { ok: false, error: "Something went wrong. Please try again." };
  }
  revalidatePath("/users");
  return { ok: true };
}
