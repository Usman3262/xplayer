import { redirect } from "next/navigation";
import { Suspense } from "react";

import { createClient } from "@/lib/supabase/server";

/** Placeholder home: the real dashboard arrives in Phase 2. */
export default function Home() {
  return (
    <main className="flex flex-1 items-center justify-center p-8">
      <div className="space-y-2 text-center">
        <h1 className="text-2xl font-semibold">Admin</h1>
        {/* Session is read at request time, so it streams in behind Suspense. */}
        <Suspense
          fallback={<p className="text-muted-foreground text-sm">Loading…</p>}
        >
          <SignedInAs />
        </Suspense>
      </div>
    </main>
  );
}

async function SignedInAs() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  return (
    <p className="text-muted-foreground text-sm">
      Signed in as {user.email}. Dashboard coming in Phase 2.
    </p>
  );
}
