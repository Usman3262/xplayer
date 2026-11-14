import "server-only";
import { createClient } from "@supabase/supabase-js";

import { publicEnv } from "@/lib/env";
import type { Database } from "@/lib/supabase/database.types";
import { serverEnv } from "@/lib/env.server";

/**
 * Service-role client: BYPASSES RLS. Only for trusted server code that has
 * already checked the caller's admin permission (see requirePermission).
 * Never import from client components (enforced by `server-only`).
 */
export function createAdminClient() {
  return createClient<Database>(
    publicEnv.NEXT_PUBLIC_SUPABASE_URL,
    serverEnv().SUPABASE_SECRET_KEY,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );
}
