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

import { UserStatusActions } from "./user-controls";

export const metadata = { title: "Users" };

type Row = {
  id: string;
  email: string;
  display_name: string | null;
  status: "active" | "suspended" | "banned";
  is_admin: boolean;
  email_confirmed: boolean;
  created_at: string;
  last_sign_in_at: string | null;
  last_seen_at: string | null;
};

const STATUSES = ["active", "suspended", "banned"] as const;
const PAGE_SIZE = 25;

export default function UsersPage({ searchParams }: PageProps<"/users">) {
  return (
    <>
      <PageHeader
        title="Users"
        description="People who created an optional app account. Guests (no account) don't appear here; their data stays on their device."
      />
      <Suspense fallback={<CardsSkeleton count={4} />}>
        <UsersContent searchParams={searchParams} />
      </Suspense>
    </>
  );
}

const dt = new Intl.DateTimeFormat("en", { dateStyle: "medium", timeStyle: "short" });
const when = (iso: string | null) => (iso ? dt.format(new Date(iso)) : null);

async function UsersContent({ searchParams }: { searchParams: Promise<SearchParamsRecord> }) {
  const admin = await requirePermission("users.read", "/users");
  const canWrite = admin.can("users.write");
  const sp = await searchParams;
  const { q, filters } = parseTableParams(sp, { filterKeys: ["status", "before", "bid"] });
  const status = STATUSES.find((s) => s === filters.status);
  const supabase = await createClient();

  // Keyset paging: newest first; "before"/"bid" = last row of the previous page.
  const [list, counts] = await Promise.all([
    supabase.rpc("admin_list_users", {
      p_search: q || undefined,
      p_status: status,
      p_before_created: filters.before,
      p_before_id: filters.bid,
      p_limit: PAGE_SIZE + 1,
    }),
    supabase.rpc("admin_user_counts"),
  ]);
  if (list.error) return <ErrorState description="Users could not be loaded. Refresh to try again." />;

  const all = (list.data ?? []) as Row[];
  const rows = all.slice(0, PAGE_SIZE);
  const last = rows.at(-1);
  const hasMore = all.length > PAGE_SIZE;
  const c = counts.data?.[0];

  const columns: Column<Row>[] = [
    {
      key: "user",
      header: "User",
      cell: (r) => (
        <div className="min-w-0 space-y-0.5">
          <p className="truncate text-sm font-medium">{r.display_name || r.email}</p>
          {r.display_name ? <p className="text-muted-foreground truncate text-xs">{r.email}</p> : null}
        </div>
      ),
    },
    {
      key: "status",
      header: "Status",
      className: "w-40",
      cell: (r) => (
        <div className="flex flex-wrap gap-1.5">
          <StatusBadge status={r.status} />
          {r.is_admin ? <Badge className="bg-primary/15 text-primary rounded-full">Admin</Badge> : null}
          {!r.email_confirmed ? <Badge className="bg-secondary text-muted-foreground rounded-full">Unconfirmed</Badge> : null}
        </div>
      ),
    },
    {
      key: "joined",
      header: "Joined",
      className: "w-44 whitespace-nowrap",
      cell: (r) => <span className="text-muted-foreground text-sm tabular-nums">{when(r.created_at)}</span>,
    },
    {
      key: "last",
      header: "Last sign-in",
      className: "w-44 whitespace-nowrap",
      cell: (r) => <span className="text-muted-foreground text-sm tabular-nums">{when(r.last_sign_in_at) ?? "Never"}</span>,
    },
    ...(canWrite
      ? [
          {
            key: "actions",
            header: "",
            className: "w-56",
            cell: (r: Row) =>
              r.is_admin || r.id === admin.userId ? null : <UserStatusActions userId={r.id} email={r.email} status={r.status} />,
          },
        ]
      : []),
  ];

  return (
    <div className="flex flex-col gap-5">
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <Stat label="Accounts" value={c?.total} />
        <Stat label="New this week" value={c?.last_7_days} />
        <Stat label="Suspended" value={c?.suspended} />
        <Stat label="Banned" value={c?.banned} />
      </div>
      <TableToolbar
        searchPlaceholder="Search email or name"
        filters={[{ key: "status", label: "Status", options: STATUSES.map((s) => ({ value: s, label: s[0].toUpperCase() + s.slice(1) })) }]}
      />
      <DataTable
        columns={columns}
        rows={rows}
        rowKey={(r) => r.id}
        path="/users"
        searchParams={sp}
        page={1}
        pageSize={PAGE_SIZE}
        hasNext={false}
        emptyTitle={q || status ? "No matching users" : "No accounts yet"}
        emptyDescription="Accounts appear here when someone creates one in the app (it's optional)."
      />
      <div className="flex justify-end gap-2">
        {filters.before ? (
          <Link href={withParams("/users", sp, { before: null, bid: null })} className={cn(buttonVariants({ variant: "ghost" }), "rounded-full")}>
            Back to newest
          </Link>
        ) : null}
        {hasMore && last ? (
          <Link
            href={withParams("/users", sp, { before: last.created_at, bid: last.id })}
            className={cn(buttonVariants({ variant: "outline" }), "rounded-full")}
          >
            Older users <ChevronRight />
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

function StatusBadge({ status }: { status: Row["status"] }) {
  const tone =
    status === "active"
      ? "bg-emerald-500/15 text-emerald-400"
      : status === "suspended"
        ? "bg-amber-500/15 text-amber-400"
        : "bg-destructive/15 text-destructive";
  return <Badge className={cn("rounded-full capitalize", tone)}>{status}</Badge>;
}
