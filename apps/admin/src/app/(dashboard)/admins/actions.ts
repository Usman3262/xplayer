"use server";

import { randomBytes } from "node:crypto";

import { revalidatePath } from "next/cache";
import { z } from "zod";

import { actionGuard, type ActionResult } from "@/lib/auth";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";

const ROLE_KEYS = [
  "super_admin",
  "admin",
  "content_manager",
  "subscription_manager",
  "marketing_manager",
  "support_agent",
  "analyst",
] as const;

const uuid = z.uuid();
const roleKey = z.enum(ROLE_KEYS);

/** DB safety messages (P0001) are written for people; anything else stays generic. */
function dbError(error: { code?: string; message?: string } | null): string {
  if (error?.code === "P0001" && error.message) return error.message;
  if (error?.code === "42501") return "You don't have permission for this.";
  return "Something went wrong. Please try again.";
}

export type AddAdminResult = ActionResult<{ email: string; created: boolean; tempPassword?: string }>;

/**
 * Add an admin by email. Existing account → gets the role. New email → an account is
 * created (email confirmed) with a one-time temporary password shown only to the caller.
 */
export async function addAdmin(input: { email: string; role: string }): Promise<AddAdminResult> {
  const guard = await actionGuard("admins.write");
  if ("error" in guard) return guard.error;

  const parsed = z.object({ email: z.email().max(200), role: roleKey }).safeParse(input);
  if (!parsed.success) return { ok: false, error: "Enter a valid email and pick a role." };
  const email = parsed.data.email.toLowerCase();

  const supabase = await createClient();
  const { data: existing, error: findError } = await supabase.rpc("admin_find_user", { p_email: email });
  if (findError) return { ok: false, error: dbError(findError) };

  let userId = existing as string | null;
  let tempPassword: string | undefined;
  if (!userId) {
    // Creating accounts needs the service role — allowed only after the permission check above.
    tempPassword = randomBytes(15).toString("base64url");
    const { data, error } = await createAdminClient().auth.admin.createUser({
      email,
      password: tempPassword,
      email_confirm: true,
    });
    if (error || !data.user) return { ok: false, error: "Could not create the account. Check the email and try again." };
    userId = data.user.id;
    await supabase.rpc("log_audit", {
      p_action: "create_account",
      p_entity: "auth_users",
      p_entity_id: userId,
      p_meta: { email, via: "add_admin" },
    });
  }

  const { error } = await supabase.rpc("admin_set_role", { p_user: userId, p_role_key: parsed.data.role });
  if (error) return { ok: false, error: dbError(error) };

  revalidatePath("/admins");
  return { ok: true, data: { email, created: !!tempPassword, tempPassword } };
}

export async function changeRole(userId: string, role: string): Promise<ActionResult> {
  const guard = await actionGuard("admins.write");
  if ("error" in guard) return guard.error;
  if (!uuid.safeParse(userId).success || !roleKey.safeParse(role).success) return { ok: false, error: "Invalid request." };

  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_set_role", { p_user: userId, p_role_key: role });
  if (error) return { ok: false, error: dbError(error) };
  revalidatePath("/admins");
  return { ok: true };
}

export async function setAdminActive(userId: string, active: boolean): Promise<ActionResult> {
  const guard = await actionGuard("admins.write");
  if ("error" in guard) return guard.error;
  if (!uuid.safeParse(userId).success) return { ok: false, error: "Invalid request." };

  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_set_active", { p_user: userId, p_active: active });
  if (error) return { ok: false, error: dbError(error) };
  revalidatePath("/admins");
  return { ok: true };
}

export async function removeAdmin(userId: string): Promise<ActionResult> {
  const guard = await actionGuard("admins.write");
  if ("error" in guard) return guard.error;
  if (!uuid.safeParse(userId).success) return { ok: false, error: "Invalid request." };

  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_remove", { p_user: userId });
  if (error) return { ok: false, error: dbError(error) };
  revalidatePath("/admins");
  return { ok: true };
}
