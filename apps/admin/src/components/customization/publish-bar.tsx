import { CheckCircle2, CircleDot } from "lucide-react";
import { connection } from "next/server";

import { createClient } from "@/lib/supabase/server";

import { PublishButton } from "./publish-button";

type Status = {
  version: number;
  published_at: string | null;
  notes: string | null;
  published_by: string | null;
  dirty: boolean;
  changed: string[];
  can_publish: boolean;
};

const LABELS: Record<string, string> = {
  settings: "settings",
  flags: "feature flags",
  versions: "app versions",
  maintenance: "maintenance",
  onboarding: "panel types",
  theme: "theme",
  home: "home screen",
};

/** Sticky bar on every customization page: live version + unpublished changes + Publish. */
export async function PublishBar() {
  await connection(); // session/time-dependent → request-time only
  const supabase = await createClient();
  const { data } = await supabase.rpc("admin_config_status");
  const s = data as Status | null;
  if (!s) return null;
  const when = s.published_at
    ? new Intl.DateTimeFormat("en", { dateStyle: "medium", timeStyle: "short" }).format(new Date(s.published_at))
    : "never";

  return (
    <div
      className={
        s.dirty
          ? "border-primary/40 bg-primary/10 flex flex-wrap items-center gap-4 rounded-3xl border px-5 py-4"
          : "bg-card/60 flex flex-wrap items-center gap-4 rounded-3xl border px-5 py-4"
      }
    >
      {s.dirty ? <CircleDot className="text-primary size-5 shrink-0" /> : <CheckCircle2 className="size-5 shrink-0 text-emerald-400" />}
      <div className="min-w-0 flex-1 text-sm">
        {s.dirty ? (
          <p className="font-medium">
            Unpublished changes: {s.changed.map((c) => LABELS[c] ?? c).join(", ")}
          </p>
        ) : (
          <p className="font-medium">Apps are up to date</p>
        )}
        <p className="text-muted-foreground text-xs">
          Live: version {s.version} · published {when}
          {s.published_by ? ` by ${s.published_by}` : ""}
          {s.notes ? ` · “${s.notes}”` : ""}
        </p>
      </div>
      {s.can_publish ? <PublishButton dirty={s.dirty} /> : null}
    </div>
  );
}
