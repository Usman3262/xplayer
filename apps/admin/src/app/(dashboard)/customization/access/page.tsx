import { Suspense } from "react";

import { PageHeader } from "@/components/layout/page-header";
import { CardsSkeleton, ErrorState } from "@/components/states";
import { requirePermission } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";

import { PanelList, SignInPolicyForm, type PanelType, type Policy } from "./access-controls";

export const metadata = { title: "Login & panels" };

export default function AccessPage() {
  return (
    <>
      <PageHeader title="Login & panels" description="Sign-in rules and the “Choose your panel” screen. Save, then publish." />
      <Suspense fallback={<CardsSkeleton count={4} />}>
        <AccessContent />
      </Suspense>
    </>
  );
}

const KEYS = ["auth.mode", "auth.allow_registration", "auth.guest_enabled", "providers.max_connections", "providers.connect_timeout_ms"];

async function AccessContent() {
  const admin = await requirePermission("customization.read", "/customization/access");
  const canWrite = admin.can("customization.write");
  const supabase = await createClient();
  const [settings, panels] = await Promise.all([
    supabase.from("app_settings").select("key,value").in("key", KEYS),
    supabase
      .from("onboarding_panel_types")
      .select("key,label,description,help_text,icon,is_enabled,platforms,fields")
      .order("sort_order")
      .order("key"),
  ]);
  if (settings.error || panels.error) return <ErrorState description="Login settings could not be loaded." />;

  const v = Object.fromEntries((settings.data ?? []).map((r) => [r.key, r.value]));
  const mode = v["auth.mode"];
  const policy: Policy = {
    mode: mode === "required" || mode === "disabled" ? mode : "optional",
    allow_registration: v["auth.allow_registration"] !== false,
    guest_enabled: v["auth.guest_enabled"] !== false,
    max_connections: Number(v["providers.max_connections"] ?? 5),
    connect_timeout_s: Math.round(Number(v["providers.connect_timeout_ms"] ?? 8000) / 1000),
  };

  return (
    <div className="flex flex-col gap-8">
      <SignInPolicyForm initial={policy} canWrite={canWrite} />
      <PanelList panels={(panels.data ?? []) as PanelType[]} canWrite={canWrite} />
    </div>
  );
}
