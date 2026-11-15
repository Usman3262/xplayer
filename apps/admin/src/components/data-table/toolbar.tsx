"use client";

import { Search, X } from "lucide-react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { useEffect, useRef, useState, useTransition } from "react";

import { cn } from "@/lib/utils";

export type FilterDef = {
  key: string;
  label: string;
  options: { value: string; label: string }[];
};

/**
 * Search (debounced) + select filters. Writes to the URL and resets to page 1;
 * the server page re-renders with the new params.
 */
export function TableToolbar({ filters = [], searchPlaceholder = "Search" }: { filters?: FilterDef[]; searchPlaceholder?: string }) {
  const router = useRouter();
  const pathname = usePathname();
  const params = useSearchParams();
  const [pending, startTransition] = useTransition();
  const [q, setQ] = useState(params.get("q") ?? "");
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const push = (changes: Record<string, string | null>) => {
    const next = new URLSearchParams(params.toString());
    for (const [k, v] of Object.entries(changes)) {
      if (v) next.set(k, v);
      else next.delete(k);
    }
    // A new search/filter starts from the first page (offset or cursor paging).
    for (const k of ["page", "before", "bid"]) next.delete(k);
    const s = next.toString();
    startTransition(() => router.replace(s ? `${pathname}?${s}` : pathname, { scroll: false }));
  };

  useEffect(() => () => {
    if (timer.current) clearTimeout(timer.current);
  }, []);

  const onSearch = (value: string) => {
    setQ(value);
    if (timer.current) clearTimeout(timer.current);
    timer.current = setTimeout(() => push({ q: value.trim() || null }), 300);
  };

  const active = filters.some((f) => params.get(f.key)) || !!params.get("q");

  return (
    <div className={cn("flex flex-wrap items-center gap-3 transition-opacity", pending && "opacity-70")}>
      <div className="relative w-full max-w-xs">
        <Search className="text-muted-foreground pointer-events-none absolute top-1/2 left-4 size-4 -translate-y-1/2" />
        <input
          value={q}
          onChange={(e) => onSearch(e.target.value)}
          placeholder={searchPlaceholder}
          aria-label={searchPlaceholder}
          className="bg-secondary/70 placeholder:text-muted-foreground focus:ring-primary/40 h-11 w-full rounded-full pr-4 pl-11 text-sm outline-none focus:ring-2"
        />
      </div>
      {filters.map((f) => (
        <select
          key={f.key}
          aria-label={f.label}
          value={params.get(f.key) ?? ""}
          onChange={(e) => push({ [f.key]: e.target.value || null })}
          className="bg-secondary/70 focus:ring-primary/40 h-11 rounded-full px-4 text-sm outline-none focus:ring-2"
        >
          <option value="">{f.label}: all</option>
          {f.options.map((o) => (
            <option key={o.value} value={o.value}>
              {o.label}
            </option>
          ))}
        </select>
      ))}
      {active ? (
        <button
          type="button"
          onClick={() => {
            setQ("");
            push(Object.fromEntries([["q", null], ...filters.map((f) => [f.key, null])]));
          }}
          className="text-muted-foreground hover:text-foreground flex items-center gap-1 text-sm"
        >
          <X className="size-4" /> Clear
        </button>
      ) : null}
    </div>
  );
}
