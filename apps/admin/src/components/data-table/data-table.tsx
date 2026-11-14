import { ChevronLeft, ChevronRight } from "lucide-react";
import Link from "next/link";
import type { ReactNode } from "react";

import { EmptyState } from "@/components/states";
import { buttonVariants } from "@/components/ui/button";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { cn } from "@/lib/utils";
import { type SearchParamsRecord, withParams } from "@/lib/table-params";

export type Column<T> = {
  key: string;
  header: ReactNode;
  cell: (row: T) => ReactNode;
  className?: string;
};

type Props<T> = {
  columns: Column<T>[];
  rows: T[];
  rowKey: (row: T) => string | number;
  /** Current path + search params, for pager links. */
  path: string;
  searchParams: SearchParamsRecord;
  page: number;
  /** Either an exact total, or just whether a next page exists (cheap for big tables). */
  total?: number;
  pageSize: number;
  hasNext?: boolean;
  emptyTitle?: string;
  emptyDescription?: string;
};

/**
 * Server-rendered table with URL-based paging. Rows are fetched by the page with
 * the user's session (RLS / permission-checked RPCs) — this component only renders.
 */
export function DataTable<T>({
  columns,
  rows,
  rowKey,
  path,
  searchParams,
  page,
  total,
  pageSize,
  hasNext,
  emptyTitle = "Nothing here yet",
  emptyDescription,
}: Props<T>) {
  if (rows.length === 0 && page === 1) {
    return <EmptyState title={emptyTitle} description={emptyDescription} />;
  }
  const next = total !== undefined ? page * pageSize < total : !!hasNext;
  const from = (page - 1) * pageSize + 1;
  const to = from + rows.length - 1;

  return (
    <div className="bg-card/60 overflow-hidden rounded-[28px] border">
      <Table>
        <TableHeader>
          <TableRow className="hover:bg-transparent">
            {columns.map((c) => (
              <TableHead key={c.key} className={cn("text-muted-foreground h-12 px-5 text-xs font-medium uppercase", c.className)}>
                {c.header}
              </TableHead>
            ))}
          </TableRow>
        </TableHeader>
        <TableBody>
          {rows.map((row) => (
            <TableRow key={rowKey(row)}>
              {columns.map((c) => (
                <TableCell key={c.key} className={cn("px-5 py-3 align-top", c.className)}>
                  {c.cell(row)}
                </TableCell>
              ))}
            </TableRow>
          ))}
        </TableBody>
      </Table>

      <div className="flex items-center justify-between gap-4 border-t px-5 py-3 text-sm">
        <span className="text-muted-foreground">
          {rows.length ? `${from}–${to}` : "0"}
          {total !== undefined ? ` of ${total}` : ""}
        </span>
        <div className="flex items-center gap-2">
          <PagerLink href={withParams(path, searchParams, { page: page > 2 ? page - 1 : null })} disabled={page <= 1} label="Previous">
            <ChevronLeft className="size-4" />
          </PagerLink>
          <span className="text-muted-foreground px-1 tabular-nums">Page {page}</span>
          <PagerLink href={withParams(path, searchParams, { page: page + 1 })} disabled={!next} label="Next">
            <ChevronRight className="size-4" />
          </PagerLink>
        </div>
      </div>
    </div>
  );
}

function PagerLink({ href, disabled, label, children }: { href: string; disabled: boolean; label: string; children: ReactNode }) {
  const cls = cn(buttonVariants({ variant: "outline", size: "icon" }), "rounded-xl");
  if (disabled) {
    return (
      <span aria-disabled className={cn(cls, "pointer-events-none opacity-40")} aria-label={label}>
        {children}
      </span>
    );
  }
  return (
    <Link href={href} className={cls} aria-label={label} scroll={false}>
      {children}
    </Link>
  );
}
