import { Suspense } from "react";

import { PageHeader } from "@/components/layout/page-header";
import { CardsSkeleton } from "@/components/states";
import { requireAdmin } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";

import { PasswordForm, TwoFactorSetup } from "./account-forms";

export const metadata = { title: "My account" };

export default function AccountPage({ searchParams }: PageProps<"/account">) {
  return (
    <>
      <PageHeader title="My account" description="Your sign-in details and security." />
      <Suspense fallback={<CardsSkeleton count={2} />}>
        <AccountContent searchParams={searchParams} />
      </Suspense>
    </>
  );
}

async function AccountContent({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const admin = await requireAdmin({ next: "/account", allowWithout2fa: true });
  const sp = await searchParams;
  const supabase = await createClient();
  const { data } = await supabase.rpc("admin_security_state");
  const sec = data as { require_2fa: boolean } | null;
  const mustSetUp = !admin.has2fa && (sec?.require_2fa || sp.setup === "2fa");

  return (
    <div className="grid gap-6 xl:grid-cols-2">
      <section className="bg-card/60 space-y-5 rounded-[28px] border p-6 md:p-8">
        <div>
          <h2 className="font-semibold">Two-factor sign-in</h2>
          <p className="text-muted-foreground text-sm">A code from your phone on every sign-in.</p>
        </div>
        {mustSetUp ? (
          <p className="bg-primary/10 text-primary rounded-2xl p-3 text-sm">
            Two-factor sign-in is required for admins. Set it up to continue using the panel.
          </p>
        ) : null}
        <TwoFactorSetup enabled={admin.has2fa} required={!!sec?.require_2fa} />
      </section>

      <section className="bg-card/60 space-y-5 rounded-[28px] border p-6 md:p-8">
        <div>
          <h2 className="font-semibold">Password</h2>
          <p className="text-muted-foreground text-sm">Signed in as {admin.email}</p>
        </div>
        <PasswordForm />
      </section>
    </div>
  );
}
