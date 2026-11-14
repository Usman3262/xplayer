"use client";

import { ArrowDown, ArrowUp, CalendarClock, ChevronsUp, Globe, Lock, Pencil, Plus, Trash2 } from "lucide-react";
import { useState, useTransition } from "react";
import { toast } from "sonner";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Switch } from "@/components/ui/switch";
import { LAYOUTS, SECTION_TYPES, SOURCES, type LayoutKey, type SourceKey } from "@/lib/home-sections";
import { cn } from "@/lib/utils";

import { deleteSection, moveSection, setSectionEnabled } from "./actions";
import { HomePreview } from "./home-preview";
import { SectionDialog, type SectionRow, type Top10Option } from "./section-dialog";

export function HomeBuilder({ sections, canWrite, top10Lists }: { sections: SectionRow[]; canWrite: boolean; top10Lists: Top10Option[] }) {
  const [pending, start] = useTransition();
  const [editing, setEditing] = useState<SectionRow | null>(null);
  const [creating, setCreating] = useState(false);
  const [platform, setPlatform] = useState<"android" | "tv">("android");

  const run = (fn: () => Promise<{ ok: boolean; error?: string }>, ok?: string) =>
    start(async () => {
      const res = await fn();
      if (res.ok) {
        if (ok) toast.success(ok);
      } else toast.error(res.error ?? "Failed");
    });

  return (
    <div className="grid gap-8 2xl:grid-cols-[minmax(0,1fr)_auto]">
      <section className="flex min-w-0 flex-col gap-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <h2 className="font-semibold">Sections</h2>
            <p className="text-muted-foreground text-sm">Top to bottom, as on the app&apos;s home screen.</p>
          </div>
          {canWrite ? (
            <Button className="rounded-full" onClick={() => setCreating(true)}>
              <Plus /> Add section
            </Button>
          ) : null}
        </div>

        <ul className="space-y-3">
          {sections.map((s, i) => {
            const type = SECTION_TYPES[s.section_type];
            const scheduled = s.starts_at || s.ends_at;
            return (
              <li key={s.id} className={cn("bg-card/60 flex flex-wrap items-center gap-3 rounded-3xl border p-4", !s.is_enabled && "opacity-55")}>
                <span className="bg-secondary text-muted-foreground flex size-9 shrink-0 items-center justify-center rounded-xl text-sm tabular-nums">{i + 1}</span>
                <div className="min-w-0 flex-1">
                  <p className="truncate font-medium">{s.title}</p>
                  <div className="mt-1 flex flex-wrap gap-1.5">
                    <Badge className="bg-secondary text-foreground rounded-full font-normal">{type?.label ?? s.section_type}</Badge>
                    <Badge className="bg-primary/12 text-primary rounded-full font-normal">{SOURCES[s.source as SourceKey]?.label ?? s.source}</Badge>
                    <Badge className="bg-secondary text-muted-foreground rounded-full font-normal">{LAYOUTS[s.layout as LayoutKey] ?? s.layout}</Badge>
                    {s.source === "manual" ? <Badge className="bg-secondary text-muted-foreground rounded-full font-normal">{s.home_section_items.length} picks</Badge> : null}
                    {s.platforms?.length ? <Badge className="bg-secondary text-muted-foreground rounded-full font-normal">{s.platforms.join(", ")}</Badge> : null}
                    {s.countries?.length ? (
                      <Badge className="bg-secondary text-muted-foreground gap-1 rounded-full font-normal">
                        <Globe className="size-3" /> {s.countries.join(", ")}
                      </Badge>
                    ) : null}
                    {s.requires_login ? (
                      <Badge className="bg-secondary text-muted-foreground gap-1 rounded-full font-normal">
                        <Lock className="size-3" /> signed in
                      </Badge>
                    ) : null}
                    {scheduled ? (
                      <Badge className="gap-1 rounded-full bg-amber-500/15 font-normal text-amber-300">
                        <CalendarClock className="size-3" /> scheduled
                      </Badge>
                    ) : null}
                  </div>
                </div>
                {canWrite ? (
                  <div className="flex items-center gap-1">
                    <Button size="icon" variant="ghost" className="rounded-full" disabled={pending || i === 0} aria-label={`Move ${s.title} to top`} onClick={() => run(() => moveSection(s.id, "top"))}>
                      <ChevronsUp />
                    </Button>
                    <Button size="icon" variant="ghost" className="rounded-full" disabled={pending || i === 0} aria-label={`Move ${s.title} up`} onClick={() => run(() => moveSection(s.id, "up"))}>
                      <ArrowUp />
                    </Button>
                    <Button size="icon" variant="ghost" className="rounded-full" disabled={pending || i === sections.length - 1} aria-label={`Move ${s.title} down`} onClick={() => run(() => moveSection(s.id, "down"))}>
                      <ArrowDown />
                    </Button>
                    <Button size="icon" variant="ghost" className="rounded-full" aria-label={`Edit ${s.title}`} onClick={() => setEditing(s)}>
                      <Pencil />
                    </Button>
                    <Button
                      size="icon"
                      variant="ghost"
                      className="text-destructive hover:text-destructive rounded-full"
                      aria-label={`Delete ${s.title}`}
                      disabled={pending}
                      onClick={() => {
                        if (window.confirm(`Delete “${s.title}”? Turning it off keeps it for later.`)) run(() => deleteSection(s.id), "Deleted — publish to apply");
                      }}
                    >
                      <Trash2 />
                    </Button>
                  </div>
                ) : null}
                <Switch
                  checked={s.is_enabled}
                  disabled={!canWrite || pending}
                  aria-label={`${s.title} ${s.is_enabled ? "shown" : "hidden"}`}
                  onCheckedChange={(v) => run(() => setSectionEnabled(s.id, v), v ? "Shown — publish to apply" : "Hidden — publish to apply")}
                />
              </li>
            );
          })}
        </ul>
      </section>

      <aside className="flex flex-col items-center gap-3 2xl:sticky 2xl:top-6 2xl:self-start">
        <div className="bg-secondary/60 flex rounded-full p-1 text-xs">
          {(["android", "tv"] as const).map((p) => (
            <button key={p} type="button" onClick={() => setPlatform(p)} className={cn("rounded-full px-4 py-1.5", platform === p ? "bg-primary text-primary-foreground" : "text-muted-foreground")}>
              {p === "tv" ? "TV" : "Phone"}
            </button>
          ))}
        </div>
        <HomePreview sections={sections.filter((s) => s.is_enabled && (!s.platforms?.length || s.platforms.includes(platform)))} />
        <p className="text-muted-foreground max-w-[260px] text-center text-xs">Approximate preview of the app&apos;s home. Real titles come from each user&apos;s panel.</p>
      </aside>

      {creating ? <SectionDialog open onOpenChange={(o) => !o && setCreating(false)} row={null} top10Lists={top10Lists} /> : null}
      {editing ? <SectionDialog key={editing.id} open onOpenChange={(o) => !o && setEditing(null)} row={editing} top10Lists={top10Lists} /> : null}
    </div>
  );
}
