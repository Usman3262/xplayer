import "server-only";
import { redirect } from "next/navigation";
import { connection } from "next/server";
import { cache } from "react";

import { createClient } from "@/lib/supabase/server";

export type AdminSession = {
  userId: string;
  email: string | null;
  permissions: ReadonlySet<string>;
  can: (perm: string) => boolean;
  /** Admin has a verified authenticator (TOTP). */
  has2fa: boolean;
};

type SecurityState = { require_2fa: boolean; has_2fa: boolean; aal: string } | null;

/**
 * Where the current visitor stands. The DB enforces the same rules: with a
 * verified 2FA factor, every permission needs an aal2 session.
 */
export type AdminGate =
  | { status: "signed_out" }
  | { status: "not_admin" }
  | { status: "mfa_required" } // has 2FA, this session hasn't entered the code yet
  | { status: "setup_2fa"; admin: AdminSession } // policy requires 2FA, none set up
  | { status: "ok"; admin: AdminSession };

export const getAdminGate = cache(async (): Promise<AdminGate> => {
  // Session checks use the current time (token expiry) → always request-time.
  await connection();
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return { status: "signed_out" };

  const { data: secData } = await supabase.rpc("admin_security_state");
  const sec = secData as SecurityState;
  if (!sec) return { status: "not_admin" };
  if (sec.has_2fa && sec.aal !== "aal2") return { status: "mfa_required" };

  const { data, error } = await supabase.rpc("my_permissions");
  if (error || !data || data.length === 0) return { status: "not_admin" };

  const permissions = new Set<string>(data as string[]);
  const admin: AdminSession = {
    userId: user.id,
    email: user.email ?? null,
    permissions,
    can: (perm) => permissions.has(perm),
    has2fa: sec.has_2fa,
  };
  if (sec.require_2fa && !sec.has_2fa) return { status: "setup_2fa", admin };
  return { status: "ok", admin };
});

/** The usable admin for this request (fully verified), or null. */
export async function getAdmin(): Promise<AdminSession | null> {
  const gate = await getAdminGate();
  return gate.status === "ok" ? gate.admin : null;
}

/**
 * For pages/layouts: redirect unless the visitor is a fully verified admin.
 * `allowWithout2fa` lets the shell and /account render while 2FA is being set up.
 */
export async function requireAdmin(opts: { next?: string; allowWithout2fa?: boolean } = {}): Promise<AdminSession> {
  const gate = await getAdminGate();
  const next = opts.next ? `?next=${encodeURIComponent(opts.next)}` : "";
  switch (gate.status) {
    case "signed_out":
    case "not_admin":
      redirect(`/login${next}`);
    case "mfa_required":
      redirect(`/login/mfa${next}`);
    case "setup_2fa":
      if (opts.allowWithout2fa) return gate.admin;
      redirect("/account?setup=2fa");
    case "ok":
      return gate.admin;
  }
}

/** For pages: admin with `perm`, otherwise the forbidden page. */
export async function requirePermission(perm: string, next?: string): Promise<AdminSession> {
  const admin = await requireAdmin({ next });
  if (!admin.can(perm)) redirect("/forbidden");
  return admin;
}

/** Result shape for server actions (never throw raw errors to the client). */
export type ActionResult<T = undefined> =
  | { ok: true; data?: T }
  | { ok: false; error: string };

/**
 * For server actions: returns the admin or an error result. Server actions are
 * public HTTP endpoints, so every action must call this first.
 */
export async function actionGuard(
  perm: string,
): Promise<{ admin: AdminSession } | { error: ActionResult<never> }> {
  const gate = await getAdminGate();
  if (gate.status === "mfa_required") return { error: { ok: false, error: "Enter your two-factor code first." } };
  if (gate.status === "setup_2fa") return { error: { ok: false, error: "Turn on two-factor sign-in first (My account)." } };
  if (gate.status !== "ok") return { error: { ok: false, error: "Please sign in again." } };
  if (!gate.admin.can(perm)) return { error: { ok: false, error: "You don't have permission for this." } };
  return { admin: gate.admin };
}

/** Only allow same-site relative redirects (blocks open redirects like //evil.com). */
export function safeNext(next: unknown, fallback = "/"): string {
  if (typeof next !== "string") return fallback;
  if (!next.startsWith("/") || next.startsWith("//") || next.startsWith("/\\")) return fallback;
  return next;
}
