import { Suspense } from "react";

import { PageHeader } from "@/components/layout/page-header";
import { CardsSkeleton, ErrorState } from "@/components/states";
import { requirePermission } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";

import { Top10Manager, type Top10Row } from "./top10-manager";

export const metadata = { title: "Top 10" };

export default function Top10Page() {
  return (
    <>
      <PageHeader title="Top 10" description="Ranked lists for the home screen — from the user's panel or your own ranking. Save, then publish." />
      <Suspense fallback={<CardsSkeleton count={4} />}>
        <Top10Content />
      </Suspense>
    </>
  );
}

async function Top10Content() {
  const admin = await requirePermission("customization.read", "/customization/top10");
  const supabase = await createClient();
  const [lists, sections] = await Promise.all([
    supabase
      .from("top10_lists")
      .select("id,title,content_kind,source,params,country,is_enabled,top10_items(rank,item_kind,tmdb_id,match_title,panel_item_id,panel_key)")
      .order("created_at")
      .order("rank", { referencedTable: "top10_items" }),
    supabase.from("home_sections").select("top10_list_id").not("top10_list_id", "is", null),
  ]);
  if (lists.error || sections.error) return <ErrorState description="Top 10 lists could not be loaded." />;
  const used = new Map<string, number>();
  for (const s of sections.data ?? []) if (s.top10_list_id) used.set(s.top10_list_id, (used.get(s.top10_list_id) ?? 0) + 1);
  const rows = ((lists.data ?? []) as unknown as Omit<Top10Row, "used_by">[]).map((l) => ({ ...l, used_by: used.get(l.id) ?? 0 }));
  return <Top10Manager lists={rows} canWrite={admin.can("customization.write")} />;
}
