"use server";

import { createClient as createPlainClient } from "@supabase/supabase-js";
import { z } from "zod";

import { getAdminGate, type ActionResult } from "@/lib/auth";
import { publicEnv } from "@/lib/env";
import { createClient } from "@/lib/supabase/server";

const schema = z
  .object({
    current: z.string().min(1, "Enter your current password.").max(200),
    next: z.string().min(12, "Use at least 12 characters.").max(200),
    confirm: z.string(),
  })
  .refine((v) => v.next === v.confirm, { message: "The new passwords don't match.", path: ["confirm"] })
  .refine((v) => v.next !== v.current, { message: "Pick a password you haven't used here.", path: ["next"] });

/** Change own password. Verifies the current one first (Supabase doesn't). */
export async function changePassword(input: { current: string; next: string; confirm: string }): Promise<ActionResult> {
  const gate = await getAdminGate();
  // Allowed during 2FA setup; not before the 2FA code is entered.
  if (gate.status !== "ok" && gate.status !== "setup_2fa") return { ok: false, error: "Please sign in again." };
  const email = gate.admin.email;
  if (!email) return { ok: false, error: "This account has no email." };

  const parsed = schema.safeParse(input);
  if (!parsed.success) return { ok: false, error: parsed.error.issues[0]?.message ?? "Check the form." };

  // Check the current password with a throw-away client (doesn't touch this session).
  const probe = createPlainClient(publicEnv.NEXT_PUBLIC_SUPABASE_URL, publicEnv.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { error: wrong } = await probe.auth.signInWithPassword({ email, password: parsed.data.current });
  if (wrong) return { ok: false, error: "Your current password is wrong." };
  await probe.auth.signOut({ scope: "local" });

  const supabase = await createClient();
  const { error } = await supabase.auth.updateUser({ password: parsed.data.next });
  if (error) {
    return {
      ok: false,
      error: error.message?.toLowerCase().includes("weak")
        ? "That password is too weak. Use a longer one with mixed characters."
        : "Could not change the password. Please try again.",
    };
  }
  await supabase.rpc("log_audit", { p_action: "change_password", p_entity: "auth_users", p_entity_id: gate.admin.userId });
  return { ok: true };
}
