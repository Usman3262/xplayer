import { Suspense } from "react";

import { DataTable, type Column } from "@/components/data-table/data-table";
import { PageHeader } from "@/components/layout/page-header";
import { CardsSkeleton, ErrorState } from "@/components/states";
import { Badge } from "@/components/ui/badge";
import { requirePermission } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { cn } from "@/lib/utils";

import { AddAdminDialog, AdminRowActions, RoleSelect, type RoleOption } from "./admin-controls";

export const metadata = { title: "Admins & roles" };

type AdminRow = {
  user_id: string;
  email: string;
  role_key: string;
  role_name: string;
  is_active: boolean;
  added_at: string;
  last_sign_in_at: string | null;
};

type RoleRow = {
  id: string;
  key: string;
  name: string;
  description: string | null;
  is_system: boolean;
  admin_role_permissions: { permission_key: string }[];
};

export default function AdminsPage() {
  return (
    <Suspense fallback={<CardsSkeleton count={4} />}>
      <AdminsContent />
    </Suspense>
  );
}

const when = (iso: string | null) =>
  iso ? new Intl.DateTimeFormat("en", { dateStyle: "medium", timeStyle: "short" }).format(new Date(iso)) : "Never";

async function AdminsContent() {
  const me = await requirePermission("admins.read", "/admins");
  const canWrite = me.can("admins.write");
  const supabase = await createClient();

  const [admins, roles] = await Promise.all([
    supabase.rpc("admin_list_admins"),
    supabase
      .from("admin_roles")
      .select("id,key,name,description,is_system,admin_role_permissions(permission_key)")
      .order("is_system", { ascending: false })
      .order("name"),
  ]);
  if (admins.error || roles.error) {
    return <ErrorState description="Admins could not be loaded. Refresh to try again." />;
  }
  const rows = (admins.data ?? []) as AdminRow[];
  const roleRows = (roles.data ?? []) as RoleRow[];
  const roleOptions: RoleOption[] = roleRows.map((r) => ({ key: r.key, name: r.name }));
  const countByRole = new Map<string, number>();
  for (const a of rows) countByRole.set(a.role_key, (countByRole.get(a.role_key) ?? 0) + 1);

  const columns: Column<AdminRow>[] = [
    {
      key: "admin",
      header: "Admin",
      cell: (r) => (
        <div className="flex items-center gap-3">
          <span className="bg-brand-gradient flex size-9 shrink-0 items-center justify-center rounded-xl text-sm font-semibold text-white">
            {r.email[0]?.toUpperCase()}
          </span>
          <div className="min-w-0">
            <p className="truncate text-sm font-medium">
              {r.email}
              {r.user_id === me.userId ? <span className="text-primary ml-2 text-xs">(you)</span> : null}
            </p>
            <p className="text-muted-foreground text-xs">Added {when(r.added_at)}</p>
          </div>
        </div>
      ),
    },
    {
      key: "role",
      header: "Role",
      className: "w-56",
      cell: (r) =>
        canWrite && r.user_id !== me.userId ? (
          <RoleSelect userId={r.user_id} value={r.role_key} roles={roleOptions} />
        ) : (
          <Badge className="bg-secondary text-foreground rounded-full">{r.role_name}</Badge>
        ),
    },
    {
      key: "status",
      header: "Status",
      className: "w-28",
      cell: (r) => (
        <Badge className={cn("rounded-full", r.is_active ? "bg-emerald-500/15 text-emerald-400" : "bg-secondary text-muted-foreground")}>
          {r.is_active ? "Active" : "Inactive"}
        </Badge>
      ),
    },
    {
      key: "seen",
      header: "Last sign-in",
      className: "w-48 whitespace-nowrap",
      cell: (r) => <span className="text-muted-foreground text-sm">{when(r.last_sign_in_at)}</span>,
    },
    ...(canWrite
      ? [
          {
            key: "actions",
            header: "",
            className: "w-52",
            cell: (r: AdminRow) =>
              r.user_id === me.userId ? null : <AdminRowActions userId={r.user_id} email={r.email} active={r.is_active} />,
          },
        ]
      : []),
  ];

  return (
    <>
      <PageHeader
        title="Admins & roles"
        description="Who can use this panel and what each role may do."
        actions={canWrite ? <AddAdminDialog roles={roleOptions} /> : null}
      />

      <DataTable
        columns={columns}
        rows={rows}
        rowKey={(r) => r.user_id}
        path="/admins"
        searchParams={{}}
        page={1}
        pageSize={Math.max(rows.length, 1)}
        total={rows.length}
        emptyTitle="No admins"
      />

      <section className="space-y-4">
        <h2 className="text-lg font-semibold">Roles</h2>
        <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
          {roleRows.map((r) => {
            const perms = r.admin_role_permissions.map((p) => p.permission_key).sort();
            const modules = new Map<string, string[]>();
            for (const p of perms) {
              const [mod, act] = p.split(".");
              modules.set(mod, [...(modules.get(mod) ?? []), act]);
            }
            return (
              <div key={r.id} className="bg-card/60 rounded-[28px] border p-6">
                <div className="flex items-start justify-between gap-3">
                  <div>
                    <p className="font-semibold">{r.name}</p>
                    <p className="text-muted-foreground text-sm">{r.description}</p>
                  </div>
                  <span className="text-muted-foreground shrink-0 text-xs">
                    {countByRole.get(r.key) ?? 0} admin{(countByRole.get(r.key) ?? 0) === 1 ? "" : "s"}
                  </span>
                </div>
                <div className="mt-4 flex flex-wrap gap-1.5">
                  {r.key === "super_admin" ? (
                    <Badge className="bg-primary/15 text-primary rounded-full">Everything</Badge>
                  ) : (
                    [...modules.entries()].map(([mod, acts]) => (
                      <Badge key={mod} className="bg-secondary text-foreground rounded-full font-normal">
                        {mod} · {acts.join(", ")}
                      </Badge>
                    ))
                  )}
                </div>
                {r.is_system ? <p className="text-muted-foreground mt-4 text-xs">Built-in role (read-only)</p> : null}
              </div>
            );
          })}
        </div>
      </section>
    </>
  );
}
