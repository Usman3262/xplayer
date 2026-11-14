"use client";

import { ChevronDown, LogOut } from "lucide-react";

import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuGroup,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";

import { signOut } from "@/app/login/actions";

/** Profile chip (avatar, name, role) like the reference top bar. */
export function UserMenu({ email, roleSummary }: { email: string; roleSummary: string }) {
  const name = email.split("@")[0] || email;
  const initials = (name[0] ?? "?").toUpperCase();
  return (
    <DropdownMenu>
      <DropdownMenuTrigger className="hover:bg-secondary/70 flex items-center gap-3 rounded-2xl border p-1.5 pr-3 transition-colors outline-none">
        <Avatar className="size-10 rounded-xl">
          <AvatarFallback className="bg-brand-gradient rounded-xl text-sm font-semibold text-white">{initials}</AvatarFallback>
        </Avatar>
        <span className="hidden flex-col items-start leading-tight sm:flex">
          <span className="max-w-40 truncate text-sm font-medium">{name}</span>
          <span className="text-muted-foreground text-xs">{roleSummary}</span>
        </span>
        <ChevronDown className="text-muted-foreground size-4" />
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-60">
        <DropdownMenuGroup>
          <DropdownMenuLabel className="space-y-0.5">
            <span className="block truncate text-sm">{email}</span>
            <span className="text-muted-foreground block text-xs font-normal">{roleSummary}</span>
          </DropdownMenuLabel>
        </DropdownMenuGroup>
        <DropdownMenuSeparator />
        <DropdownMenuItem onClick={() => void signOut()}>
          <LogOut />
          Sign out
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
