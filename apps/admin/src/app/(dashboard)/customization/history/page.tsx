import { Suspense } from "react";

import { PageHeader } from "@/components/layout/page-header";
import { CardsSkeleton, ErrorState } from "@/components/states";
import { Badge } from "@/components/ui/badge";
import { requirePermission } from "@/lib/auth";
import { fmtDateTime } from "@/lib/dates";
import { createClient } from "@/lib/supabase/server";

import { RollbackButton } from "./rollback-button";

export const metadata = { title: "Publish history" };

type Row = { version: number; notes: string | null; published_at: string; published_by: string | null; size_bytes: number; restored_from: number | null };

export default function HistoryPage() {
  return (
    <>
      <PageHeader title="Publish history" description="Every version sent to the apps. Roll back in an emergency." />
      <Suspense fallback={<CardsSkeleton count={4} />}>
        <HistoryContent />
      </Suspense>
    </>
  );
}

async function HistoryContent() {
  const admin = await requirePermission("customization.read", "/customization/history");
  const { data, error } = await (await createClient()).rpc("admin_config_history", { p_limit: 50 });
  if (error) return <ErrorState description="Publish history could not be loaded." />;
  const rows = (data ?? []) as Row[];
  const canPublish = admin.can("customization.publish");

  return (
    <section className="bg-card/60 overflow-hidden rounded-[28px] border">
      <ul className="divide-y">
        {rows.map((r, i) => (
          <li key={r.version} className="flex flex-wrap items-center gap-4 px-6 py-4">
            <span className="bg-secondary flex size-11 shrink-0 items-center justify-center rounded-2xl text-sm font-semibold tabular-nums">v{r.version}</span>
            <div className="min-w-0 flex-1">
              <p className="flex flex-wrap items-center gap-2 text-sm font-medium">
                {r.notes ?? <span className="text-muted-foreground font-normal">No note</span>}
                {i === 0 ? <Badge className="rounded-full bg-emerald-500/15 text-emerald-400">Live</Badge> : null}
                {r.restored_from ? <Badge className="rounded-full bg-amber-500/15 text-amber-300">rollback of v{r.restored_from}</Badge> : null}
              </p>
              <p className="text-muted-foreground text-xs">
                {fmtDateTime(r.published_at)} · {r.published_by ?? "system"} · {(r.size_bytes / 1024).toFixed(1)} KB
              </p>
            </div>
            {canPublish && i > 0 ? <RollbackButton version={r.version} /> : null}
          </li>
        ))}
      </ul>
    </section>
  );
}
