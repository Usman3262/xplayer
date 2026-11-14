import { Suspense } from "react";

import { PageHeader } from "@/components/layout/page-header";
import { CardsSkeleton, ErrorState } from "@/components/states";
import { requirePermission } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";

import { BannerManager, type BannerRow } from "./banner-manager";

export const metadata = { title: "Banners" };

export default function BannersPage() {
  return (
    <>
      <PageHeader title="Banners" description="Hero banners on the home screen. Save, then publish." />
      <Suspense fallback={<CardsSkeleton count={4} />}>
        <BannersContent />
      </Suspense>
    </>
  );
}

async function BannersContent() {
  const admin = await requirePermission("customization.read", "/customization/banners");
  const { data, error } = await (await createClient())
    .from("banners")
    .select("id,title,subtitle,image_url,image_url_tv,cta_label,action_type,action_value,item_kind,tmdb_id,panel_item_id,panel_key,platforms,countries,requires_login,starts_at,ends_at,is_enabled")
    .order("sort_order")
    .order("created_at");
  if (error) return <ErrorState description="Banners could not be loaded." />;
  return <BannerManager banners={(data ?? []) as BannerRow[]} canWrite={admin.can("customization.write")} />;
}
