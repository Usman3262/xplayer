import { CalendarClock, Smartphone, Tv } from "lucide-react";
import { Suspense } from "react";

import { TableToolbar } from "@/components/data-table/toolbar";
import { PageHeader } from "@/components/layout/page-header";
import { CardsSkeleton, EmptyState, ErrorState } from "@/components/states";
import { Badge } from "@/components/ui/badge";
import { requirePermission } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { parseTableParams, type SearchParamsRecord } from "@/lib/table-params";

import { FlagEditDialog, FlagSwitch, type FlagRow } from "./flag-controls";
import { OverridesPanel, type OverrideRow } from "./overrides-panel";

export const metadata = { title: "Feature flags" };

export default function FlagsPage({ searchParams }: PageProps<"/customization/flags">) {
  return (
    <>
      <PageHeader title="Feature flags" description="Turn app features on or off — per platform, app version or schedule. Publish to apply." />
      <Suspense fallback={<CardsSkeleton count={6} />}>
        <FlagsContent searchParams={searchParams} />
      </Suspense>
    </>
  );
}

const fmt = (iso: string) => new Intl.DateTimeFormat("en", { dateStyle: "medium", timeStyle: "short" }).format(new Date(iso));

async function FlagsContent({ searchParams }: { searchParams: Promise<SearchParamsRecord> }) {
  const admin = await requirePermission("customization.read", "/customization/flags");
  const canWrite = admin.can("customization.write");
  const { q, filters } = parseTableParams(await searchParams, { filterKeys: ["state"] });

  const supabase = await createClient();
  let query = supabase
    .from("feature_flags")
    .select("key,name,description,enabled,platforms,min_app_version,max_app_version,starts_at,ends_at")
    .order("name");
  if (filters.state === "on") query = query.eq("enabled", true);
  if (filters.state === "off") query = query.eq("enabled", false);
  if (q) query = query.or(`name.ilike.%${q.replace(/[%,()]/g, "")}%,key.ilike.%${q.replace(/[%,()]/g, "")}%`);
  const [{ data, error }, overrides, allFlags] = await Promise.all([
    query,
    supabase.rpc("admin_flag_overrides"),
    supabase.from("feature_flags").select("key,name").order("name"),
  ]);
  if (error) return <ErrorState description="Feature flags could not be loaded." />;
  const flags = (data ?? []) as FlagRow[];

  return (
    <div className="flex flex-col gap-5">
      <OverridesPanel rows={(overrides.data ?? []) as OverrideRow[]} flags={allFlags.data ?? []} canWrite={canWrite} />
      <TableToolbar
        searchPlaceholder="Search features"
        filters={[{ key: "state", label: "State", options: [{ value: "on", label: "On" }, { value: "off", label: "Off" }] }]}
      />
      {flags.length === 0 ? (
        <EmptyState title="No matching features" />
      ) : (
        <div className="grid gap-4 md:grid-cols-2 2xl:grid-cols-3">
          {flags.map((f) => (
            <div key={f.key} className="bg-card/60 flex flex-col gap-3 rounded-[28px] border p-5">
              <div className="flex items-start justify-between gap-3">
                <div className="min-w-0">
                  <p className="font-semibold">{f.name}</p>
                  <p className="text-muted-foreground text-sm">{f.description}</p>
                </div>
                <FlagSwitch flag={f} disabled={!canWrite} />
              </div>
              <div className="flex flex-wrap items-center gap-1.5">
                <Badge className="bg-secondary text-muted-foreground rounded-full font-mono font-normal">{f.key}</Badge>
                {f.platforms?.length ? (
                  f.platforms.map((p) => (
                    <Badge key={p} className="bg-secondary text-foreground gap-1 rounded-full font-normal">
                      {p === "tv" ? <Tv className="size-3" /> : <Smartphone className="size-3" />}
                      {p === "ios" ? "iPhone" : p === "tv" ? "TV" : "Android"}
                    </Badge>
                  ))
                ) : (
                  <Badge className="bg-secondary text-muted-foreground rounded-full font-normal">All platforms</Badge>
                )}
                {f.min_app_version || f.max_app_version ? (
                  <Badge className="bg-secondary text-foreground rounded-full font-normal">
                    v{f.min_app_version ?? "0"} – {f.max_app_version ? `v${f.max_app_version}` : "latest"}
                  </Badge>
                ) : null}
                {f.starts_at || f.ends_at ? (
                  <Badge className="bg-primary/15 text-primary gap-1 rounded-full font-normal">
                    <CalendarClock className="size-3" />
                    {f.starts_at ? `from ${fmt(f.starts_at)}` : ""} {f.ends_at ? `until ${fmt(f.ends_at)}` : ""}
                  </Badge>
                ) : null}
                <span className="ml-auto">{canWrite ? <FlagEditDialog flag={f} /> : null}</span>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
