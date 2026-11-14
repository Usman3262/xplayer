import "server-only";
import { z } from "zod";

/** Server-only env. Importing this from a client component fails the build. */
const serverSchema = z.object({
  SUPABASE_SECRET_KEY: z.string().min(10),
});

/** Throws a clear error if the secret key is missing (only when actually used). */
export function serverEnv() {
  const parsed = serverSchema.safeParse({
    SUPABASE_SECRET_KEY: process.env.SUPABASE_SECRET_KEY,
  });
  if (!parsed.success) {
    throw new Error(
      "SUPABASE_SECRET_KEY is missing. Add it to apps/admin/.env.local (server only).",
    );
  }
  return parsed.data;
}
