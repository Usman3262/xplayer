import { ChevronRight } from "lucide-react";
import Link from "next/link";
import { Suspense } from "react";

import { DataTable, type Column } from "@/components/data-table/data-table";
import { TableToolbar } from "@/components/data-table/toolbar";
import { PageHeader } from "@/components/layout/page-header";
import { CardsSkeleton, ErrorState } from "@/components/states";
import { Badge } from "@/components/ui/badge";
import { buttonVariants } from "@/components/ui/button";
import { requirePermission } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { parseTableParams, type SearchParamsRecord, withParams } from "@/lib/table-params";
import { cn } from "@/lib/utils";

import { RevokeDeviceButton } from "./device-controls";

export const metadata = { title: "Devices" };

type Row = {
  user_id: string;
  email: string;
  device_id: string;
  name: string | null;
  platform: string;
  model: string | null;
  app_version: string | null;
  panel_kind: string | null;
  first_seen_at: string;
  last_seen_at: string;
  revoked_at: string | null;
};

const PAGE_SIZE = 25;
const PANEL: Record<string, string> = { xtream: "Xtream", m3u: "M3U", stalker: "Stalker / MAC" };
const PLATFORM: Record<string, string> = { android: "Android", ios: "iOS", android_tv: "Android TV", web: "Web", other: "Other" };

export default function DevicesPage({ searchParams }: PageProps<"/devices">) {
  return (
    <>
      <PageHeader
        title="Devices"
        description="Phones and TVs where someone is signed in to an app account. Guests are not listed. No panel logins or stream links are stored here."
      />
      <Suspense fallback={<CardsSkeleton count={3} />}>
        <DevicesContent searchParams={searchParams} />
      </Suspense>
    </>
  );
}

const dt = new Intl.DateTimeFormat("en", { dateStyle: "medium", timeStyle: "short" });
const when = (iso: string | null) => (iso ? dt.format(new Date(iso)) : null);

async function DevicesContent({ searchParams }: { searchParams: Promise<SearchParamsRecord> }) {
  const admin = await requirePermission("devices.read", "/devices");
  const canWrite = admin.can("devices.write");
  const sp = await searchParams;
  const { q, filters } = parseTableParams(sp, { filterKeys: ["before"] });
  const supabase = await createClient();

  const [list, counts] = await Promise.all([
    supabase.rpc("admin_list_devices", { p_search: q || undefined, p_before_seen: filters.before, p_limit: PAGE_SIZE + 1 }),
    supabase.rpc("admin_device_counts"),
  ]);
  if (list.error) return <ErrorState description="Devices could not be loaded. Refresh to try again." />;

  const all = (list.data ?? []) as Row[];
  const rows = all.slice(0, PAGE_SIZE);
  const last = rows.at(-1);
  const hasMore = all.length > PAGE_SIZE;
  const c = (counts.data as { total: number; active_7_days: number; revoked: number }[] | null)?.[0];

  const columns: Column<Row>[] = [
    {
      key: "device",
      header: "Device",
      cell: (r) => (
        <div className="min-w-0 space-y-0.5">
          <p className="truncate text-sm font-medium">{r.name || r.model || "Unknown device"}</p>
          <p className="text-muted-foreground truncate text-xs">
            {PLATFORM[r.platform] ?? r.platform}
            {r.app_version ? ` · app ${r.app_version}` : ""}
            {r.panel_kind ? ` · ${PANEL[r.panel_kind] ?? r.panel_kind}` : ""}
          </p>
        </div>
      ),
    },
    {
      key: "user",
      header: "Account",
      cell: (r) => <span className="text-muted-foreground truncate text-sm">{r.email}</span>,
    },
    {
      key: "state",
      header: "State",
      className: "w-32",
      cell: (r) =>
        r.revoked_at ? (
          <Badge className="bg-destructive/15 text-destructive rounded-full">Signed out</Badge>
        ) : (
          <Badge className="rounded-full bg-emerald-500/15 text-emerald-400">Active</Badge>
        ),
    },
    {
      key: "seen",
      header: "Last seen",
      className: "w-44 whitespace-nowrap",
      cell: (r) => <span className="text-muted-foreground text-sm tabular-nums">{when(r.last_seen_at)}</span>,
    },
    ...(canWrite
      ? [
          {
            key: "actions",
            header: "",
            className: "w-32",
            cell: (r: Row) =>
              r.revoked_at ? null : (
                <div className="flex justify-end">
                  <RevokeDeviceButton userId={r.user_id} deviceId={r.device_id} label={r.name || r.model || "this device"} />
                </div>
              ),
          },
        ]
      : []),
  ];

  return (
    <div className="flex flex-col gap-5">
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
        <Stat label="Devices" value={c?.total} />
        <Stat label="Active this week" value={c?.active_7_days} />
        <Stat label="Signed out by user or admin" value={c?.revoked} />
      </div>
      <TableToolbar searchPlaceholder="Search email, model or device id" filters={[]} />
      <DataTable
        columns={columns}
        rows={rows}
        rowKey={(r) => `${r.user_id}:${r.device_id}`}
        path="/devices"
        searchParams={sp}
        page={1}
        pageSize={PAGE_SIZE}
        hasNext={false}
        emptyTitle={q ? "No matching devices" : "No devices yet"}
        emptyDescription="A device appears when someone signs in to an app account on it."
      />
      <div className="flex justify-end gap-2">
        {filters.before ? (
          <Link href={withParams("/devices", sp, { before: null })} className={cn(buttonVariants({ variant: "ghost" }), "rounded-full")}>
            Back to most recent
          </Link>
        ) : null}
        {hasMore && last ? (
          <Link
            href={withParams("/devices", sp, { before: last.last_seen_at })}
            className={cn(buttonVariants({ variant: "outline" }), "rounded-full")}
          >
            Older <ChevronRight />
          </Link>
        ) : null}
      </div>
    </div>
  );
}

function Stat({ label, value }: { label: string; value: number | undefined }) {
  return (
    <div className="bg-card rounded-3xl border p-5">
      <p className="text-muted-foreground text-sm">{label}</p>
      <p className="mt-1 text-2xl font-semibold tabular-nums">{value ?? "—"}</p>
    </div>
  );
}
