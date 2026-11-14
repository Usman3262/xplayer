import { Suspense } from "react";

import { PageHeader } from "@/components/layout/page-header";
import { CardsSkeleton, ErrorState } from "@/components/states";
import { requirePermission } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";

import { HomeBuilder } from "./home-builder";
import type { SectionRow } from "./section-dialog";

export const metadata = { title: "Home builder" };

export default function HomeBuilderPage() {
  return (
    <>
      <PageHeader title="Home builder" description="What the apps' home screen shows, in which order, to whom. Save, then publish." />
      <Suspense fallback={<CardsSkeleton count={6} />}>
        <HomeContent />
      </Suspense>
    </>
  );
}

async function HomeContent() {
  const admin = await requirePermission("customization.read", "/customization/home");
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("home_sections")
    .select(
      "id,title,subtitle,section_type,content_kind,source,layout,item_limit,params,platforms,countries,requires_login,starts_at,ends_at,is_enabled," +
        "home_section_items(item_kind,tmdb_id,match_title,panel_item_id,panel_key,title,image_url,deep_link,sort_order)",
    )
    .order("sort_order")
    .order("created_at")
    .order("sort_order", { referencedTable: "home_section_items" });
  if (error) return <ErrorState description="Home sections could not be loaded." />;
  return <HomeBuilder sections={(data ?? []) as unknown as SectionRow[]} canWrite={admin.can("customization.write")} />;
}
