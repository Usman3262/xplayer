import { Suspense } from "react";

import { SettingsCard, type SettingRow } from "@/components/customization/settings-card";
import { PageHeader } from "@/components/layout/page-header";
import { CardsSkeleton, ErrorState } from "@/components/states";
import { requirePermission } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";

import { MaintenanceList, VersionCard, type MaintenanceRow, type VersionRow } from "./version-controls";

export const metadata = { title: "Versions & maintenance" };

export default function VersionsPage() {
  return (
    <>
      <PageHeader title="Versions & maintenance" description="Update rules, maintenance windows and player/cache defaults. Save, then publish." />
      <Suspense fallback={<CardsSkeleton count={6} />}>
        <VersionsContent />
      </Suspense>
    </>
  );
}

const PLAYER_KEYS = ["player.live_format", "player.retry_count", "player.buffer_seconds", "player.progress_save_s"];
const CACHE_KEYS = ["cache.catalog_ttl_hours", "cache.epg_retention_hours", "cache.image_cache_mb", "config.refresh_interval_s", "search.min_chars"];

const LABELS: Record<string, string> = {
  "player.live_format": "Live stream format",
  "player.retry_count": "Automatic retries",
  "player.buffer_seconds": "Buffer",
  "player.progress_save_s": "Save watch progress every",
  "cache.catalog_ttl_hours": "Refresh panel catalog after",
  "cache.epg_retention_hours": "Keep TV guide for",
  "cache.image_cache_mb": "Image cache on device",
  "config.refresh_interval_s": "Apps check for new settings every",
  "search.min_chars": "Start searching after",
};
const UNITS: Record<string, string> = {
  "player.buffer_seconds": "s",
  "player.progress_save_s": "s",
  "cache.catalog_ttl_hours": "h",
  "cache.epg_retention_hours": "h",
  "cache.image_cache_mb": "MB",
  "config.refresh_interval_s": "s",
  "search.min_chars": "chars",
};

async function VersionsContent() {
  const admin = await requirePermission("customization.read", "/customization/versions");
  const canWrite = admin.can("customization.write");
  const supabase = await createClient();
  const [versions, maintenance, settings] = await Promise.all([
    supabase.from("app_versions").select("platform,min_version,recommended_version,latest_version,update_url,release_notes"),
    supabase
      .from("maintenance_windows")
      .select("id,title,message,platforms,starts_at,ends_at,is_active")
      .order("starts_at", { ascending: false })
      .limit(20),
    supabase.from("app_settings").select("key,value_type,value,validation,description").in("key", [...PLAYER_KEYS, ...CACHE_KEYS]),
  ]);
  if (versions.error || maintenance.error || settings.error) {
    return <ErrorState description="These settings could not be loaded." />;
  }
  const order = { android: 0, ios: 1, tv: 2 } as const;
  const vRows = ((versions.data ?? []) as VersionRow[]).sort((a, b) => order[a.platform] - order[b.platform]);
  const sRows = (settings.data ?? []) as SettingRow[];
  const pick = (keys: string[]) => keys.map((k) => sRows.find((r) => r.key === k)).filter((r): r is SettingRow => !!r);

  return (
    <div className="flex flex-col gap-8">
      <section className="space-y-4">
        <h2 className="text-lg font-semibold">App versions</h2>
        <div className="grid gap-4 xl:grid-cols-3">
          {vRows.map((r) => (
            <VersionCard key={r.platform} row={r} canWrite={canWrite} />
          ))}
        </div>
      </section>

      <MaintenanceList rows={(maintenance.data ?? []) as MaintenanceRow[]} canWrite={canWrite} now={nowMs()} />

      <div className="grid gap-6 2xl:grid-cols-2">
        <SettingsCard title="Player" description="Defaults for every user; users can change some in their settings." rows={pick(PLAYER_KEYS)} labels={LABELS} units={UNITS} canWrite={canWrite} />
        <SettingsCard title="Cache & refresh" description="How long the apps keep data before refreshing." rows={pick(CACHE_KEYS)} labels={LABELS} units={UNITS} canWrite={canWrite} />
      </div>
    </div>
  );
}

/** Current time for "now / scheduled / finished" badges (request-time page). */
function nowMs(): number {
  return Date.now();
}
