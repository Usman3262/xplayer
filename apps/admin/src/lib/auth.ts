import "server-only";
import { redirect } from "next/navigation";
import { cache } from "react";

import { createClient } from "@/lib/supabase/server";

export type AdminSession = {
  userId: string;
  email: string | null;
  permissions: ReadonlySet<string>;
  can: (perm: string) => boolean;
};

/**
 * The signed-in admin for this request, or null (not signed in / not an admin).
 * Verified with Supabase (`getUser`, never `getSession`); cached per request.
 * Permissions come from the DB (`my_permissions()`), the same source RLS uses.
 */
export const getAdmin = cache(async (): Promise<AdminSession | null> => {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const { data, error } = await supabase.rpc("my_permissions");
  if (error || !data || data.length === 0) return null;

  const permissions = new Set<string>(data as string[]);
  return {
    userId: user.id,
    email: user.email ?? null,
    permissions,
    can: (perm) => permissions.has(perm),
  };
});

/** For pages/layouts: redirect to /login unless the visitor is an admin. */
export async function requireAdmin(next?: string): Promise<AdminSession> {
  const admin = await getAdmin();
  if (!admin) {
    redirect(next ? `/login?next=${encodeURIComponent(next)}` : "/login");
  }
  return admin;
}

/** For pages: admin with `perm`, otherwise the forbidden page. */
export async function requirePermission(perm: string, next?: string): Promise<AdminSession> {
  const admin = await requireAdmin(next);
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
  const admin = await getAdmin();
  if (!admin) return { error: { ok: false, error: "Please sign in again." } };
  if (!admin.can(perm)) return { error: { ok: false, error: "You don't have permission for this." } };
  return { admin };
}

/** Only allow same-site relative redirects (blocks open redirects like //evil.com). */
export function safeNext(next: unknown, fallback = "/"): string {
  if (typeof next !== "string") return fallback;
  if (!next.startsWith("/") || next.startsWith("//") || next.startsWith("/\\")) return fallback;
  return next;
}
