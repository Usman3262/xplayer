"use client";

import { ChevronRight } from "lucide-react";
import { useState } from "react";

import type { DashboardStats } from "@/lib/dashboard-types";
import { cn } from "@/lib/utils";

const COLORS = ["bg-primary", "bg-[#ff6b74]", "bg-[var(--brand-gold)]", "bg-[#8b8b93]", "bg-[#7a0c14]"];
const when = (iso: string) =>
  new Intl.DateTimeFormat("en", { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" }).format(new Date(iso));
const fmt = new Intl.NumberFormat("en");

/** Right rail like the reference: soft panel, two tabs, message-style cards. */
export function DashboardRail({ stats }: { stats: DashboardStats }) {
  const canSeeActivity = stats.recent_activity !== null;
  const [tab, setTab] = useState<"stats" | "activity">(canSeeActivity ? "activity" : "stats");

  return (
    <aside className="bg-secondary/40 h-fit rounded-[40px] p-5 xl:sticky xl:top-6">
      <div className="mb-5 flex border-b">
        {(["stats", "activity"] as const)
          .filter((t) => t === "stats" || canSeeActivity)
          .map((t) => (
            <button
              key={t}
              type="button"
              onClick={() => setTab(t)}
              className={cn(
                "flex-1 pb-3 text-sm font-medium capitalize transition-colors",
                tab === t ? "text-foreground border-primary -mb-px border-b-2" : "text-muted-foreground",
              )}
            >
              {t}
            </button>
          ))}
      </div>

      {tab === "activity" && stats.recent_activity ? (
        <ul className="space-y-4">
          {stats.recent_activity.length === 0 ? (
            <li className="text-muted-foreground rounded-3xl p-5 text-center text-sm">No admin activity yet.</li>
          ) : (
            stats.recent_activity.map((a, i) => {
              const who = a.actor_email?.split("@")[0] ?? "System";
              return (
                <li key={a.id} className="bg-card rounded-3xl p-4">
                  <div className="flex items-start justify-between">
                    <span className={cn("flex size-9 items-center justify-center rounded-xl text-sm font-semibold text-white", COLORS[i % COLORS.length])}>
                      {who[0]?.toUpperCase()}
                    </span>
                    <span className="text-muted-foreground text-[10px]">{when(a.created_at)}</span>
                  </div>
                  <div className="mt-3 flex items-center justify-between gap-2">
                    <div className="min-w-0">
                      <p className="truncate text-sm font-medium">{who}</p>
                      <p className="text-muted-foreground truncate text-xs">
                        {a.action} · {a.entity.replaceAll("_", " ")}
                      </p>
                    </div>
                    <ChevronRight className="text-muted-foreground size-4 shrink-0" />
                  </div>
                </li>
              );
            })
          )}
        </ul>
      ) : (
        <ul className="space-y-4">
          {[
            { label: "Users", value: stats.users.total, hint: `${fmt.format(stats.users.guests)} guests` },
            { label: "Active this week", value: stats.users.active_7d, hint: `${fmt.format(stats.users.new_7d)} new` },
            { label: "Matches today", value: stats.sports.today, hint: `${stats.sports.live} live · ${stats.sports.upcoming} upcoming` },
            { label: "Panel types", value: stats.customization.panel_types, hint: "on “Choose your panel”" },
            { label: "Admins", value: stats.users.admins, hint: stats.users.suspended ? `${stats.users.suspended} users suspended` : "no suspended users" },
          ].map((row, i) => (
            <li key={row.label} className="bg-card flex items-center gap-4 rounded-3xl p-4">
              <span className={cn("size-9 shrink-0 rounded-xl", COLORS[i % COLORS.length])} />
              <div className="min-w-0 flex-1">
                <p className="text-muted-foreground text-xs">{row.label}</p>
                <p className="text-lg font-semibold tabular-nums">{fmt.format(row.value)}</p>
                <p className="text-muted-foreground truncate text-xs">{row.hint}</p>
              </div>
            </li>
          ))}
        </ul>
      )}
    </aside>
  );
}
