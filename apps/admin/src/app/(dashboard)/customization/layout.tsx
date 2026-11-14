import { Suspense, type ReactNode } from "react";

import { PublishBar } from "@/components/customization/publish-bar";
import { Skeleton } from "@/components/ui/skeleton";

/** Every App Customization page shows the live version + unpublished changes on top. */
export default function CustomizationLayout({ children }: { children: ReactNode }) {
  return (
    <>
      <Suspense fallback={<Skeleton className="h-[74px] rounded-3xl" />}>
        <PublishBar />
      </Suspense>
      {children}
    </>
  );
}
