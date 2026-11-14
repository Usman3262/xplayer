"use client";

import { Search } from "lucide-react";
import { useRouter } from "next/navigation";
import { useId, useState } from "react";

import { NAV } from "@/config/nav";

/** Big rounded search pill. For now it jumps to admin pages by name (Enter). */
export function NavSearch({ permissions }: { permissions: string[] }) {
  const router = useRouter();
  const listId = useId();
  const [q, setQ] = useState("");
  const allowed = new Set(permissions);
  const pages = NAV.flatMap((g) => g.items).filter((i) => i.ready && allowed.has(i.permission));

  return (
    <form
      role="search"
      className="relative w-full max-w-md"
      onSubmit={(e) => {
        e.preventDefault();
        const term = q.trim().toLowerCase();
        const hit = pages.find((p) => p.title.toLowerCase().includes(term));
        if (term && hit) router.push(hit.href);
      }}
    >
      <Search className="text-muted-foreground pointer-events-none absolute top-1/2 left-5 size-5 -translate-y-1/2" />
      <input
        value={q}
        onChange={(e) => setQ(e.target.value)}
        list={listId}
        placeholder="Search"
        aria-label="Search admin pages"
        className="bg-secondary/70 placeholder:text-muted-foreground focus:ring-primary/40 h-12 w-full rounded-full pr-5 pl-14 text-sm outline-none focus:ring-2"
      />
      <datalist id={listId}>
        {pages.map((p) => (
          <option key={p.href} value={p.title} />
        ))}
      </datalist>
    </form>
  );
}
