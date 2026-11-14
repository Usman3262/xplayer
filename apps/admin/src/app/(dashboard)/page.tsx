import { ChevronRight } from "lucide-react";
import { Suspense } from "react";

import { DashboardRail } from "@/components/dashboard/rail";
import { CardsSkeleton, ErrorState } from "@/components/states";
import { requirePermission } from "@/lib/auth";
import type { DashboardStats } from "@/lib/dashboard-types";
import { createClient } from "@/lib/supabase/server";

export const metadata = { title: "Dashboard" };


export default function DashboardPage() {
  return (
    <Suspense fallback={<CardsSkeleton count={6} />}>
      <DashboardContent />
    </Suspense>
  );
}

const fmt = new Intl.NumberFormat("en");
const dateFmt = new Intl.DateTimeFormat("en", { day: "numeric", month: "short" });

async function DashboardContent() {
  const admin = await requirePermission("dashboard.read", "/");
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("admin_dashboard_stats");
  if (error || !data) {
    return <ErrorState description="The dashboard numbers could not be loaded. Refresh to try again." />;
  }
  const s = data as unknown as DashboardStats;
  const name = (admin.email ?? "").split("@")[0] || "there";

  return (
    <div className="grid gap-8 xl:grid-cols-[minmax(0,1fr)_340px]">
      <div className="flex min-w-0 flex-col gap-8">
        {/* Greeting */}
        <div className="space-y-2">
          <p className="text-primary text-lg font-semibold">👋 Hey {name}!</p>
          <h1 className="text-2xl font-bold tracking-tight md:text-3xl">
            {s.customization.maintenance_now
              ? "Maintenance mode is on for the apps."
              : `Config v${s.config?.version ?? 0} is live with ${fmt.format(s.users.total)} users.`}
          </h1>
        </div>

        <SignupsChart weeks={s.signups_weekly ?? []} newThisWeek={s.users.new_7d} />

        <div className="grid gap-6 lg:grid-cols-2">
          <FeaturesDonut on={s.customization.flags_on} total={s.customization.flags_total} sections={s.customization.sections} />
          <CatalogBars catalog={s.catalog} />
        </div>
      </div>

      <DashboardRail stats={s} />
    </div>
  );
}

/** Big rounded card with a weekly bar chart (pure CSS, no chart library). */
function SignupsChart({ weeks, newThisWeek }: { weeks: { week: string; count: number }[]; newThisWeek: number }) {
  const max = Math.max(1, ...weeks.map((w) => w.count));
  const ticks = [1, 0.75, 0.5, 0.25, 0].map((t) => Math.round(max * t));
  return (
    <section className="bg-card/60 rounded-[32px] border p-6 md:p-8">
      <div className="mb-6 flex flex-wrap items-center justify-between gap-2">
        <div>
          <h2 className="font-semibold">New users</h2>
          <p className="text-muted-foreground text-sm">Last 6 weeks · {fmt.format(newThisWeek)} in the last 7 days</p>
        </div>
      </div>
      <div className="relative flex h-64 gap-4">
        <div className="text-muted-foreground flex w-10 shrink-0 flex-col justify-between text-right text-xs tabular-nums">
          {ticks.map((t, i) => (
            <span key={i}>{fmt.format(t)}</span>
          ))}
        </div>
        <div className="relative flex flex-1 items-end gap-3 md:gap-6">
          <div className="pointer-events-none absolute inset-0 flex flex-col justify-between">
            {ticks.map((_, i) => (
              <div key={i} className="border-border/70 border-t border-dashed" />
            ))}
          </div>
          {weeks.map((w, i) => {
            const h = Math.max(4, (w.count / max) * 100);
            const last = i === weeks.length - 1;
            return (
              <div key={w.week} className="relative flex h-full flex-1 flex-col items-center justify-end gap-2">
                <div
                  title={`${fmt.format(w.count)} sign-ups`}
                  className={
                    last
                      ? "bg-brand-gradient w-full max-w-20 rounded-2xl shadow-lg shadow-red-950/40"
                      : "bg-primary/25 w-full max-w-20 rounded-2xl"
                  }
                  style={{ height: `${h}%` }}
                />
              </div>
            );
          })}
        </div>
      </div>
      <div className="mt-3 flex gap-3 pl-14 md:gap-6">
        {weeks.map((w, i) => (
          <span key={w.week} className="text-muted-foreground flex-1 text-center text-xs">
            {i === weeks.length - 1 ? "This week" : dateFmt.format(new Date(w.week))}
          </span>
        ))}
      </div>
    </section>
  );
}

function FeaturesDonut({ on, total, sections }: { on: number; total: number; sections: number }) {
  const pct = total ? Math.round((on / total) * 100) : 0;
  return (
    <section className="bg-card/60 rounded-[32px] border p-6 md:p-8">
      <h2 className="font-semibold">Features enabled</h2>
      <div className="flex justify-center py-6">
        <div
          className="relative flex size-44 items-center justify-center rounded-full"
          style={{ background: `conic-gradient(var(--primary) ${pct * 3.6}deg, color-mix(in oklab, var(--primary) 18%, transparent) 0deg)` }}
        >
          <div className="bg-background flex size-32 items-center justify-center rounded-full">
            <span className="text-primary text-2xl font-semibold">{pct}%</span>
          </div>
        </div>
      </div>
      <div className="flex justify-between gap-4">
        <Legend dot="bg-primary/20" value={total - on} label="Turned off" />
        <Legend dot="bg-primary" value={on} label="Turned on" />
        <Legend dot="bg-[var(--brand-gold)]" value={sections} label="Home sections" />
      </div>
    </section>
  );
}

function Legend({ dot, value, label }: { dot: string; value: number; label: string }) {
  return (
    <div>
      <div className="flex items-center gap-2">
        <span className={`size-4 rounded-md ${dot}`} />
        <span className="text-2xl font-semibold tabular-nums">{fmt.format(value)}</span>
      </div>
      <p className="text-muted-foreground mt-1 text-xs">{label}</p>
    </div>
  );
}

function CatalogBars({ catalog }: { catalog: DashboardStats["catalog"] }) {
  const rows = [
    { key: "m", label: "Movies", value: catalog.movies, color: "bg-primary" },
    { key: "s", label: "Series", value: catalog.series, color: "bg-[#ff6b74]" },
    { key: "e", label: "Episodes", value: catalog.episodes, color: "bg-[var(--brand-gold)]" },
    { key: "c", label: "Channels", value: catalog.channels, color: "bg-[#8b8b93]" },
  ];
  const max = Math.max(1, ...rows.map((r) => r.value));
  return (
    <section className="bg-card/60 rounded-[32px] border p-6 md:p-8">
      <h2 className="font-semibold">Titles with metadata</h2>
      <div className="mt-6 flex h-28 items-end gap-2">
        {rows.map((r) => (
          <div key={r.key} className="flex flex-1 flex-col items-center justify-end gap-1">
            <span className="text-xs tabular-nums">{fmt.format(r.value)}</span>
            <div className={`w-full rounded-t-lg ${r.color}`} style={{ height: `${Math.max(6, (r.value / max) * 80)}px` }} />
          </div>
        ))}
      </div>
      <p className="text-primary mt-5 text-sm font-medium">
        Fetched on demand from TMDB: <span className="text-lg font-semibold">{fmt.format(catalog.movies + catalog.series)}</span>
      </p>
      <ul className="mt-4 space-y-2.5">
        {rows.map((r) => (
          <li key={r.key} className="flex items-center gap-3 text-sm">
            <span className={`flex size-5 items-center justify-center rounded-md text-[10px] font-semibold text-white ${r.color}`}>
              {r.key}
            </span>
            <span className="text-muted-foreground">{r.label}</span>
            <ChevronRight className="text-muted-foreground/40 ml-auto size-4" />
          </li>
        ))}
      </ul>
    </section>
  );
}
