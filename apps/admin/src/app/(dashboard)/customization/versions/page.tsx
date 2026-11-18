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
const CONTENT_KEYS = ["content.adult_section", "content.adult_keywords", "content.metadata_in_lists"];
const DIAG_KEYS = ["diagnostics.remote_logs", "diagnostics.log_retention_days"];
const PANEL_KEYS = ["providers.request_timeout_ms", "providers.list_timeout_ms", "providers.request_concurrency"];
const CACHE_KEYS = ["cache.catalog_ttl_hours", "cache.live_ttl_hours", "cache.refresh_cooldown_min", "cache.sync_parallel_categories", "cache.sync_gap_ms", "cache.sync_cooldown_min", "cache.epg_retention_hours", "cache.image_cache_mb", "config.refresh_interval_s", "search.min_chars"];

const LABELS: Record<string, string> = {
  "player.live_format": "Live stream format",
  "player.retry_count": "Automatic retries",
  "player.buffer_seconds": "Buffer",
  "player.progress_save_s": "Save watch progress every",
  "cache.catalog_ttl_hours": "Refresh panel catalog after",
  "cache.sync_parallel_categories": "Categories synced at once",
  "cache.sync_gap_ms": "Pause between category requests",
  "cache.sync_cooldown_min": "Wait after a panel stops answering",
  "cache.epg_retention_hours": "Keep TV guide for",
  "cache.image_cache_mb": "Image cache on device",
  "config.refresh_interval_s": "Apps check for new settings every",
  "search.min_chars": "Start searching after",
  "providers.request_timeout_ms": "Catalog request timeout",
  "diagnostics.remote_logs": "Apps upload diagnostic logs",
  "content.adult_section": "Adult 18+ section (PIN)",
  "content.adult_keywords": "18+ words in category names",
  "diagnostics.log_retention_days": "Keep app logs for",
  "providers.request_concurrency": "Parallel requests per panel",
  "content.metadata_in_lists": "Posters/plots from our server for list titles too",
  "providers.list_timeout_ms": "Wait for a whole-list answer",
  "cache.live_ttl_hours": "Refresh live channels after",
  "cache.refresh_cooldown_min": "Refresh button pause after a refresh",
};
const UNITS: Record<string, string> = {
  "player.buffer_seconds": "s",
  "player.progress_save_s": "s",
  "cache.catalog_ttl_hours": "h",
  "cache.epg_retention_hours": "h",
  "cache.image_cache_mb": "MB",
  "config.refresh_interval_s": "s",
  "search.min_chars": "chars",
  "cache.sync_gap_ms": "ms",
  "cache.sync_cooldown_min": "min",
  "providers.request_timeout_ms": "ms",
  "diagnostics.log_retention_days": "days",
  "providers.list_timeout_ms": "ms",
  "cache.live_ttl_hours": "h",
  "cache.refresh_cooldown_min": "min",
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
    supabase.from("app_settings").select("key,value_type,value,validation,description").in("key", [...PLAYER_KEYS, ...CACHE_KEYS, ...PANEL_KEYS, ...DIAG_KEYS, ...CONTENT_KEYS]),
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
        <SettingsCard title="Panel connections" description="How the apps talk to users' panels (login timeout and panel limit are under Access)." rows={pick(PANEL_KEYS)} labels={LABELS} units={UNITS} canWrite={canWrite} />
        <SettingsCard title="Adult content" description="18+ categories are hidden everywhere in the apps. With the section on, an Adult 18+ button opens them after a PIN (the panel PIN on MAG/Stalker, an XPlayer PIN on Xtream/M3U)." rows={pick(CONTENT_KEYS)} labels={LABELS} units={UNITS} canWrite={canWrite} />
        <SettingsCard title="Diagnostics" description="Important app log lines (panel requests, sync, sign-in, crashes) are uploaded for support. Scrubbed on the device: no passwords, MACs or stream links." rows={pick(DIAG_KEYS)} labels={LABELS} units={UNITS} canWrite={canWrite} />
      </div>
    </div>
  );
}

/** Current time for "now / scheduled / finished" badges (request-time page). */
function nowMs(): number {
  return Date.now();
}
