import { Suspense } from "react";

import { Button } from "@/components/ui/button";
import { requireAdmin } from "@/lib/auth";

import { signOut } from "./login/actions";

/** Placeholder home until the dashboard layout (step 2.2). */
export default function Home() {
  return (
    <main className="flex flex-1 items-center justify-center p-8">
      <Suspense fallback={<p className="text-muted-foreground text-sm">Loading…</p>}>
        <Welcome />
      </Suspense>
    </main>
  );
}

async function Welcome() {
  const admin = await requireAdmin("/");
  return (
    <div className="space-y-4 text-center">
      <h1 className="text-2xl font-semibold">Admin</h1>
      <p className="text-muted-foreground text-sm">
        Signed in as {admin.email} · {admin.permissions.size} permissions
      </p>
      <form action={signOut}>
        <Button variant="outline" type="submit">
          Sign out
        </Button>
      </form>
    </div>
  );
}
