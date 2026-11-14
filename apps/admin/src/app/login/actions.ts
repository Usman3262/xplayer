"use server";

import { redirect } from "next/navigation";
import { z } from "zod";

import { safeNext } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";

export type LoginState = { error?: string; email?: string };

const schema = z.object({
  email: z.email("Enter a valid email.").max(200),
  password: z.string().min(1, "Enter your password.").max(200),
  next: z.string().max(500).optional(),
});

/** Email + password sign-in; only admins may stay signed in. */
export async function signIn(_prev: LoginState, formData: FormData): Promise<LoginState> {
  const parsed = schema.safeParse({
    email: formData.get("email"),
    password: formData.get("password"),
    next: formData.get("next") ?? undefined,
  });
  const email = String(formData.get("email") ?? "");
  if (!parsed.success) {
    return { error: parsed.error.issues[0]?.message ?? "Check your details.", email };
  }

  const supabase = await createClient();
  const { error } = await supabase.auth.signInWithPassword({
    email: parsed.data.email,
    password: parsed.data.password,
  });
  if (error) {
    // Same message for wrong email or password (don't reveal which accounts exist).
    return { error: "Wrong email or password.", email };
  }

  const { data: isAdmin } = await supabase.rpc("is_admin");
  if (!isAdmin) {
    await supabase.auth.signOut();
    return { error: "This account has no admin access.", email };
  }

  redirect(safeNext(parsed.data.next));
}

export async function signOut() {
  const supabase = await createClient();
  await supabase.auth.signOut();
  redirect("/login");
}
