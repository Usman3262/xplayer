import { AlertTriangle, Inbox } from "lucide-react";
import type { ReactNode } from "react";

import { Skeleton } from "@/components/ui/skeleton";

/** Nothing to show yet (never a blank screen). */
export function EmptyState({ title, description, action }: { title: string; description?: string; action?: ReactNode }) {
  return (
    <div className="flex flex-col items-center justify-center gap-3 rounded-2xl border border-dashed p-10 text-center">
      <span className="bg-secondary text-muted-foreground flex size-11 items-center justify-center rounded-full">
        <Inbox className="size-5" />
      </span>
      <div className="space-y-1">
        <p className="font-medium">{title}</p>
        {description ? <p className="text-muted-foreground text-sm">{description}</p> : null}
      </div>
      {action}
    </div>
  );
}

/** Something failed; useful, non-sensitive message + optional retry. */
export function ErrorState({ title = "Couldn't load this", description, action }: { title?: string; description?: string; action?: ReactNode }) {
  return (
    <div className="border-destructive/30 bg-destructive/5 flex flex-col items-center justify-center gap-3 rounded-2xl border p-10 text-center">
      <span className="bg-destructive/15 text-destructive flex size-11 items-center justify-center rounded-full">
        <AlertTriangle className="size-5" />
      </span>
      <div className="space-y-1">
        <p className="font-medium">{title}</p>
        {description ? <p className="text-muted-foreground text-sm">{description}</p> : null}
      </div>
      {action}
    </div>
  );
}

/** Grid of card skeletons for loading dashboards/lists. */
export function CardsSkeleton({ count = 4 }: { count?: number }) {
  return (
    <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
      {Array.from({ length: count }, (_, i) => (
        <Skeleton key={i} className="h-28 rounded-2xl" />
      ))}
    </div>
  );
}
