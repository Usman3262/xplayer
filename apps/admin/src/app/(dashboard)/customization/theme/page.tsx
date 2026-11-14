import { Suspense } from "react";

import { PageHeader } from "@/components/layout/page-header";
import { CardsSkeleton, ErrorState } from "@/components/states";
import { requirePermission } from "@/lib/auth";
import { publicEnv } from "@/lib/env";
import { createClient } from "@/lib/supabase/server";
import { normalizeTheme } from "@/lib/theme-tokens";

import { ThemeEditor } from "./theme-editor";

export const metadata = { title: "Branding & theme" };

export default function ThemePage() {
  return (
    <>
      <PageHeader title="Branding & theme" description="Colours, logo and name the apps use. Save, then publish." />
      <Suspense fallback={<CardsSkeleton count={4} />}>
        <ThemeContent />
      </Suspense>
    </>
  );
}

async function ThemeContent() {
  const admin = await requirePermission("customization.read", "/customization/theme");
  const supabase = await createClient();
  const [theme, settings] = await Promise.all([
    supabase.from("app_themes").select("tokens").eq("is_active", true).maybeSingle(),
    supabase.from("app_settings").select("key,value").like("key", "branding.%"),
  ]);
  if (theme.error || settings.error) return <ErrorState description="The theme could not be loaded." />;

  const s = Object.fromEntries((settings.data ?? []).map((r) => [r.key.replace("branding.", ""), typeof r.value === "string" ? r.value : ""]));
  return (
    <ThemeEditor
      initial={normalizeTheme(theme.data?.tokens as Record<string, unknown> | null)}
      branding={{
        display_name: s.display_name ?? "",
        tagline: s.tagline ?? "",
        logo_url: s.logo_url ?? "",
        splash_url: s.splash_url ?? "",
      }}
      appName={publicEnv.NEXT_PUBLIC_APP_NAME}
      canWrite={admin.can("customization.write")}
    />
  );
}
