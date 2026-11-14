import { Bell } from "lucide-react";
import { Suspense, type ReactNode } from "react";

import { AppSidebar } from "@/components/layout/app-sidebar";
import { NavSearch } from "@/components/layout/nav-search";
import { UserMenu } from "@/components/layout/user-menu";
import { CardsSkeleton } from "@/components/states";
import { SidebarInset, SidebarProvider, SidebarTrigger } from "@/components/ui/sidebar";
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip";
import { requireAdmin } from "@/lib/auth";
import { publicEnv } from "@/lib/env";

/** Admin shell: plain sidebar (filtered by permission) + airy top bar. Auth is checked here and again in every page/action. */
export default function DashboardLayout({ children }: { children: ReactNode }) {
  return (
    <Suspense fallback={<ShellFallback />}>
      <Shell>{children}</Shell>
    </Suspense>
  );
}

async function Shell({ children }: { children: ReactNode }) {
  const admin = await requireAdmin({ allowWithout2fa: true });
  const roleSummary = admin.can("admins.write") ? "Super admin" : `${admin.permissions.size} permissions`;
  const permissions = [...admin.permissions];

  return (
    <SidebarProvider>
      <AppSidebar appName={publicEnv.NEXT_PUBLIC_APP_NAME} permissions={permissions} />
      <SidebarInset className="bg-transparent">
        <header className="flex h-24 shrink-0 items-center gap-4 px-4 md:px-8">
          <SidebarTrigger className="md:hidden" />
          <NavSearch permissions={permissions} />
          <div className="ml-auto flex items-center gap-3">
            <Tooltip>
              <TooltipTrigger
                className="bg-secondary/70 text-muted-foreground relative flex size-12 items-center justify-center rounded-2xl"
                aria-label="Notifications (coming soon)"
              >
                <Bell className="size-5" />
              </TooltipTrigger>
              <TooltipContent>Notifications — coming soon</TooltipContent>
            </Tooltip>
            <UserMenu email={admin.email ?? ""} roleSummary={roleSummary} />
          </div>
        </header>
        <div className="flex flex-1 flex-col gap-8 px-4 pb-10 md:px-8">{children}</div>
      </SidebarInset>
    </SidebarProvider>
  );
}

function ShellFallback() {
  return (
    <div className="flex flex-1 flex-col gap-6 p-8">
      <CardsSkeleton />
    </div>
  );
}
