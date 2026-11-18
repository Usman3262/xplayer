"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";

import { actionGuard, type ActionResult } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";

const input = z.object({
  userId: z.uuid(),
  deviceId: z.string().regex(/^[a-z0-9]{8,64}$/),
  reason: z.string().trim().max(500).optional(),
});

/**
 * Revoke a user's device: it signs itself out at its next check-in. The DB
 * function re-checks devices.write and writes the audit row (with reason).
 */
export async function revokeDevice(raw: { userId: string; deviceId: string; reason?: string }): Promise<ActionResult> {
  const guard = await actionGuard("devices.write");
  if ("error" in guard) return guard.error;
  const parsed = input.safeParse(raw);
  if (!parsed.success) return { ok: false, error: "Invalid request." };

  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_revoke_device", {
    p_user: parsed.data.userId,
    p_device: parsed.data.deviceId,
    p_reason: parsed.data.reason || undefined,
  });
  if (error) {
    if (error.code === "42501") return { ok: false, error: "You don't have permission for this." };
    if (error.code === "P0002") return { ok: false, error: "This device was already signed out." };
    return { ok: false, error: "Something went wrong. Please try again." };
  }
  revalidatePath("/devices");
  return { ok: true };
}
