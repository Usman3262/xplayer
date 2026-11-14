import Link from "next/link";

import { buttonVariants } from "@/components/ui/button";

export const metadata = { title: "No access" };

export default function ForbiddenPage() {
  return (
    <main className="flex flex-1 items-center justify-center p-8">
      <div className="space-y-3 text-center">
        <h1 className="text-2xl font-semibold">No access</h1>
        <p className="text-muted-foreground text-sm">
          Your admin role doesn&apos;t include this page. Ask a super admin to change your role.
        </p>
        <Link href="/" className={buttonVariants({ variant: "outline" })}>
          Back to dashboard
        </Link>
      </div>
    </main>
  );
}
