import { Suspense } from "react";

import { DataTable, type Column } from "@/components/data-table/data-table";
import { TableToolbar } from "@/components/data-table/toolbar";
import { PageHeader } from "@/components/layout/page-header";
import { CardsSkeleton, ErrorState } from "@/components/states";
import { Badge } from "@/components/ui/badge";
import { requirePermission } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { parseTableParams, type SearchParamsRecord, sinceDaysIso } from "@/lib/table-params";
import { cn } from "@/lib/utils";

export const metadata = { title: "Audit log" };

type Row = {
  id: number;
  created_at: string;
  actor_email: string | null;
  action: string;
  entity: string;
  entity_id: string | null;
  before: Record<string, unknown> | null;
  after: Record<string, unknown> | null;
  meta: Record<string, unknown> | null;
};

const ACTIONS = ["insert", "update", "delete", "publish", "bootstrap_super_admin"];
const SINCE: Record<string, number> = { "1d": 1, "7d": 7, "30d": 30 };

export default function AuditPage({ searchParams }: PageProps<"/audit">) {
  return (
    <>
      <PageHeader title="Audit log" description="Every change made in this panel: who, what, when, and the exact before/after." />
      <Suspense fallback={<CardsSkeleton count={4} />}>
        <AuditContent searchParams={searchParams} />
      </Suspense>
    </>
  );
}

async function AuditContent({ searchParams }: { searchParams: Promise<SearchParamsRecord> }) {
  await requirePermission("audit.read", "/audit");
  const sp = await searchParams;
  const { page, pageSize, q, filters } = parseTableParams(sp, { filterKeys: ["action", "entity", "since"] });
  const supabase = await createClient();

  const days = SINCE[filters.since ?? ""];
  const [list, entities] = await Promise.all([
    supabase.rpc("admin_audit_logs", {
      p_limit: pageSize + 1, // +1 tells us if there is a next page
      p_offset: (page - 1) * pageSize,
      p_action: filters.action,
      p_entity: filters.entity,
      p_q: q || undefined,
      p_since: sinceDaysIso(days),
    }),
    supabase.rpc("admin_audit_entities"),
  ]);

  if (list.error) return <ErrorState description="The audit log could not be loaded. Refresh to try again." />;
  const all = (list.data ?? []) as unknown as Row[];
  const rows = all.slice(0, pageSize);

  const columns: Column<Row>[] = [
    {
      key: "when",
      header: "When",
      className: "w-44 whitespace-nowrap",
      cell: (r) => (
        <span className="text-muted-foreground text-sm tabular-nums">
          {new Intl.DateTimeFormat("en", { dateStyle: "medium", timeStyle: "short" }).format(new Date(r.created_at))}
        </span>
      ),
    },
    {
      key: "who",
      header: "Who",
      className: "w-56",
      cell: (r) => <span className="text-sm">{r.actor_email ?? <span className="text-muted-foreground">System</span>}</span>,
    },
    { key: "action", header: "Action", className: "w-32", cell: (r) => <ActionBadge action={r.action} /> },
    {
      key: "what",
      header: "What",
      cell: (r) => (
        <div className="space-y-0.5">
          <p className="text-sm font-medium">{r.entity.replaceAll("_", " ")}</p>
          {r.entity_id ? <p className="text-muted-foreground max-w-56 truncate font-mono text-xs">{r.entity_id}</p> : null}
        </div>
      ),
    },
    { key: "changes", header: "Changes", cell: (r) => <Changes row={r} /> },
  ];

  return (
    <div className="flex flex-col gap-5">
      <TableToolbar
        searchPlaceholder="Search id, table or email"
        filters={[
          { key: "action", label: "Action", options: ACTIONS.map((a) => ({ value: a, label: a.replaceAll("_", " ") })) },
          {
            key: "entity",
            label: "Table",
            options: ((entities.data ?? []) as string[]).map((e) => ({ value: e, label: e.replaceAll("_", " ") })),
          },
          {
            key: "since",
            label: "Time",
            options: [
              { value: "1d", label: "Last 24 hours" },
              { value: "7d", label: "Last 7 days" },
              { value: "30d", label: "Last 30 days" },
            ],
          },
        ]}
      />
      <DataTable
        columns={columns}
        rows={rows}
        rowKey={(r) => r.id}
        path="/audit"
        searchParams={sp}
        page={page}
        pageSize={pageSize}
        hasNext={all.length > pageSize}
        emptyTitle={q || Object.keys(filters).length ? "No matching changes" : "No changes yet"}
        emptyDescription="Admin changes appear here as soon as they are made."
      />
    </div>
  );
}

function ActionBadge({ action }: { action: string }) {
  const tone =
    action === "delete"
      ? "bg-destructive/15 text-destructive"
      : action === "insert"
        ? "bg-emerald-500/15 text-emerald-400"
        : action === "publish"
          ? "bg-primary/15 text-primary"
          : "bg-secondary text-foreground";
  return <Badge className={cn("rounded-full capitalize", tone)}>{action.replaceAll("_", " ")}</Badge>;
}

const IGNORED = new Set(["updated_at", "updated_by", "created_at"]);
const show = (v: unknown) => {
  if (v === null || v === undefined) return "—";
  const s = typeof v === "string" ? v : JSON.stringify(v);
  return s.length > 120 ? `${s.slice(0, 120)}…` : s;
};

/** Field-level diff for updates; summary for inserts/deletes/publishes. */
function Changes({ row }: { row: Row }) {
  const { before, after } = row;
  if (row.action === "publish") {
    const notes = (row.after?.notes ?? row.meta?.notes) as string | undefined;
    return <span className="text-muted-foreground text-sm">{notes ? `“${notes}”` : "Published a new app config version"}</span>;
  }
  if (!before && after) return <Details label="Created" entries={Object.entries(after).filter(([k]) => !IGNORED.has(k)).map(([k, v]) => [k, undefined, v])} />;
  if (before && !after) return <Details label="Deleted" entries={Object.entries(before).filter(([k]) => !IGNORED.has(k)).map(([k, v]) => [k, v, undefined])} />;
  if (!before || !after) return <span className="text-muted-foreground text-sm">—</span>;

  const keys = [...new Set([...Object.keys(before), ...Object.keys(after)])].filter(
    (k) => !IGNORED.has(k) && JSON.stringify(before[k]) !== JSON.stringify(after[k]),
  );
  if (keys.length === 0) return <span className="text-muted-foreground text-sm">No field changed</span>;
  return <Details label={`${keys.length} field${keys.length > 1 ? "s" : ""} changed`} entries={keys.map((k) => [k, before[k], after[k]])} open={keys.length <= 2} />;
}

function Details({ label, entries, open }: { label: string; entries: [string, unknown, unknown][]; open?: boolean }) {
  return (
    <details open={open} className="group text-sm">
      <summary className="text-primary cursor-pointer list-none font-medium select-none">{label}</summary>
      <dl className="mt-2 space-y-1.5">
        {entries.slice(0, 30).map(([k, from, to]) => (
          <div key={k} className="grid grid-cols-[minmax(6rem,auto)_1fr] gap-3">
            <dt className="text-muted-foreground font-mono text-xs">{k}</dt>
            <dd className="font-mono text-xs break-all">
              {from !== undefined ? <span className="text-destructive/90 line-through">{show(from)}</span> : null}
              {from !== undefined && to !== undefined ? <span className="text-muted-foreground"> → </span> : null}
              {to !== undefined ? <span className="text-emerald-400">{show(to)}</span> : null}
            </dd>
          </div>
        ))}
      </dl>
    </details>
  );
}
