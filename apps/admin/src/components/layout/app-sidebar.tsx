"use client";

import { ChevronDown } from "lucide-react";
import Image from "next/image";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useState } from "react";

import {
  Sidebar,
  SidebarContent,
  SidebarGroup,
  SidebarGroupContent,
  SidebarHeader,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
  SidebarRail,
  SidebarSeparator,
} from "@/components/ui/sidebar";
import { NAV } from "@/config/nav";
import { cn } from "@/lib/utils";

type Props = {
  appName: string;
  /** Serialisable list of permission keys (from the server). */
  permissions: string[];
};

/** Plain, airy sidebar: collapsible groups, quiet icons, soft red pill for the active page. */
export function AppSidebar({ appName, permissions }: Props) {
  const pathname = usePathname();
  const allowed = new Set(permissions);
  const groups = NAV.map((g) => ({ ...g, items: g.items.filter((i) => allowed.has(i.permission)) })).filter(
    (g) => g.items.length > 0,
  );
  const [closed, setClosed] = useState<ReadonlySet<string>>(new Set());
  const toggle = (label: string) =>
    setClosed((prev) => {
      const next = new Set(prev);
      if (next.has(label)) next.delete(label);
      else next.add(label);
      return next;
    });

  return (
    <Sidebar collapsible="icon" className="border-r-0">
      <SidebarHeader className="px-4 pt-6 pb-4">
        <Link href="/" className="flex items-center gap-3">
          <span className="ring-primary/40 flex size-9 shrink-0 items-center justify-center rounded-xl bg-black ring-1">
            <Image src="/brand/mark.png" alt="" width={22} height={22} priority />
          </span>
          <span className="text-2xl font-bold tracking-tight group-data-[collapsible=icon]:hidden">{appName}</span>
        </Link>
      </SidebarHeader>

      <SidebarContent className="px-2">
        {groups.map((group, gi) => {
          const isClosed = closed.has(group.label);
          return (
            <div key={group.label}>
              {gi > 0 ? <SidebarSeparator className="my-2" /> : null}
              <SidebarGroup>
                <button
                  type="button"
                  onClick={() => toggle(group.label)}
                  className="text-foreground/80 hover:text-foreground flex items-center justify-between px-2 py-2 text-sm font-semibold group-data-[collapsible=icon]:hidden"
                  aria-expanded={!isClosed}
                >
                  {group.label}
                  <ChevronDown className={cn("text-muted-foreground size-4 transition-transform", isClosed && "-rotate-90")} />
                </button>
                {!isClosed ? (
                  <SidebarGroupContent>
                    <SidebarMenu className="gap-1">
                      {group.items.map((item) => {
                        const active =
                          item.href === "/"
                            ? pathname === "/"
                            : pathname === item.href || pathname.startsWith(`${item.href}/`);
                        const Icon = item.icon;
                        return (
                          <SidebarMenuItem key={item.href}>
                            {item.ready ? (
                              <SidebarMenuButton
                                isActive={active}
                                tooltip={item.title}
                                render={<Link href={item.href} />}
                                className="text-muted-foreground hover:text-foreground h-10 rounded-xl data-[active=true]:bg-primary/12 data-[active=true]:text-primary data-[active=true]:font-medium [&_svg]:size-[18px]"
                              >
                                <Icon />
                                <span>{item.title}</span>
                              </SidebarMenuButton>
                            ) : (
                              <SidebarMenuButton
                                tooltip={`${item.title} — coming soon`}
                                aria-disabled
                                className="text-muted-foreground/50 h-10 cursor-default rounded-xl hover:bg-transparent [&_svg]:size-[18px]"
                              >
                                <Icon />
                                <span>{item.title}</span>
                                <span className="text-muted-foreground/60 ml-auto text-[10px] tracking-wide uppercase">
                                  soon
                                </span>
                              </SidebarMenuButton>
                            )}
                          </SidebarMenuItem>
                        );
                      })}
                    </SidebarMenu>
                  </SidebarGroupContent>
                ) : null}
              </SidebarGroup>
            </div>
          );
        })}
      </SidebarContent>
      <SidebarRail />
    </Sidebar>
  );
}
