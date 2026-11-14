"use client";

import { ArrowDown, ArrowUp, CalendarClock, Pencil, Plus, Trash2 } from "lucide-react";
import { useState, useTransition } from "react";
import { toast } from "sonner";

import { ImageUpload } from "@/components/customization/image-upload";
import { TargetingFields, type Targeting } from "@/components/customization/targeting-fields";
import { EmptyState } from "@/components/states";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { toLocalInput } from "@/lib/dates";
import { cn } from "@/lib/utils";

import { deleteBanner, moveBanner, saveBanner, setBannerEnabled, type BannerInput } from "./actions";

export type BannerRow = {
  id: string;
  title: string;
  subtitle: string | null;
  image_url: string;
  image_url_tv: string | null;
  cta_label: string | null;
  action_type: BannerInput["action_type"];
  action_value: string | null;
  item_kind: "movie" | "series" | "live" | null;
  tmdb_id: number | null;
  panel_item_id: string | null;
  panel_key: string | null;
  platforms: string[] | null;
  countries: string[] | null;
  requires_login: boolean;
  starts_at: string | null;
  ends_at: string | null;
  is_enabled: boolean;
};

const ACTIONS: Record<BannerInput["action_type"], string> = {
  none: "Nothing (image only)",
  content: "Open a title",
  category: "Open a category",
  screen: "Open an app screen",
  url: "Open a web link",
};
const selectCls = "bg-secondary/70 focus:ring-primary/40 h-10 w-full rounded-full px-4 text-sm outline-none focus:ring-2";

function draftOf(r: BannerRow | null): BannerInput {
  return {
    title: r?.title ?? "",
    subtitle: r?.subtitle ?? "",
    image_url: r?.image_url ?? "",
    image_url_tv: r?.image_url_tv ?? "",
    cta_label: r?.cta_label ?? "Watch now",
    action_type: r?.action_type ?? "content",
    action_value: r?.action_value ?? "",
    item_kind: r?.item_kind ?? "movie",
    tmdb_id: r?.tmdb_id ?? null,
    panel_item_id: r?.panel_item_id ?? "",
    panel_key: r?.panel_key ?? "",
    targeting: {
      platforms: (r?.platforms ?? []) as Targeting["platforms"],
      countries: r?.countries ?? [],
      requires_login: r?.requires_login ?? false,
      starts_at: toLocalInput(r?.starts_at),
      ends_at: toLocalInput(r?.ends_at),
    },
  };
}

export function BannerManager({ banners, canWrite }: { banners: BannerRow[]; canWrite: boolean }) {
  const [pending, start] = useTransition();
  const [editing, setEditing] = useState<BannerRow | "new" | null>(null);
  const run = (fn: () => Promise<{ ok: boolean; error?: string }>, ok?: string) =>
    start(async () => {
      const res = await fn();
      if (res.ok) {
        if (ok) toast.success(ok);
      } else toast.error(res.error ?? "Failed");
    });

  return (
    <section className="flex flex-col gap-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <p className="text-muted-foreground text-sm">The rotating banner at the top of the home screen, in this order.</p>
        {canWrite ? (
          <Button className="rounded-full" onClick={() => setEditing("new")}>
            <Plus /> Add banner
          </Button>
        ) : null}
      </div>
      {banners.length === 0 ? (
        <EmptyState title="No banners yet" description="Add one to feature a movie, series, match or offer." />
      ) : (
        <ul className="grid gap-4 lg:grid-cols-2">
          {banners.map((b, i) => (
            <li key={b.id} className={cn("bg-card/60 overflow-hidden rounded-[28px] border", !b.is_enabled && "opacity-55")}>
              <div className="relative aspect-[21/9] bg-black">
                {/* eslint-disable-next-line @next/next/no-img-element -- Storage URL preview */}
                <img src={b.image_url} alt="" className="size-full object-cover" />
                <div className="absolute inset-0 bg-gradient-to-t from-black/80 via-black/10 to-transparent" />
                <div className="absolute bottom-3 left-4 right-4">
                  <p className="truncate font-semibold text-white">{b.title}</p>
                  {b.subtitle ? <p className="truncate text-xs text-white/75">{b.subtitle}</p> : null}
                </div>
              </div>
              <div className="flex flex-wrap items-center gap-2 p-4">
                <Badge className="bg-secondary text-foreground rounded-full font-normal">{ACTIONS[b.action_type]}</Badge>
                {b.image_url_tv ? <Badge className="bg-secondary text-muted-foreground rounded-full font-normal">TV image</Badge> : null}
                {b.platforms?.length ? <Badge className="bg-secondary text-muted-foreground rounded-full font-normal">{b.platforms.join(", ")}</Badge> : null}
                {b.countries?.length ? <Badge className="bg-secondary text-muted-foreground rounded-full font-normal">{b.countries.join(", ")}</Badge> : null}
                {b.starts_at || b.ends_at ? (
                  <Badge className="gap-1 rounded-full bg-amber-500/15 font-normal text-amber-300">
                    <CalendarClock className="size-3" /> scheduled
                  </Badge>
                ) : null}
                <span className="ml-auto flex items-center gap-1">
                  {canWrite ? (
                    <>
                      <Button size="icon" variant="ghost" className="rounded-full" disabled={pending || i === 0} aria-label={`Move ${b.title} up`} onClick={() => run(() => moveBanner(b.id, "up"))}>
                        <ArrowUp />
                      </Button>
                      <Button size="icon" variant="ghost" className="rounded-full" disabled={pending || i === banners.length - 1} aria-label={`Move ${b.title} down`} onClick={() => run(() => moveBanner(b.id, "down"))}>
                        <ArrowDown />
                      </Button>
                      <Button size="icon" variant="ghost" className="rounded-full" aria-label={`Edit ${b.title}`} onClick={() => setEditing(b)}>
                        <Pencil />
                      </Button>
                      <Button
                        size="icon"
                        variant="ghost"
                        className="text-destructive hover:text-destructive rounded-full"
                        aria-label={`Delete ${b.title}`}
                        onClick={() => window.confirm(`Delete “${b.title}”?`) && run(() => deleteBanner(b.id), "Deleted — publish to apply")}
                      >
                        <Trash2 />
                      </Button>
                    </>
                  ) : null}
                  <Switch
                    checked={b.is_enabled}
                    disabled={!canWrite || pending}
                    aria-label={`${b.title} ${b.is_enabled ? "shown" : "hidden"}`}
                    onCheckedChange={(v) => run(() => setBannerEnabled(b.id, v), v ? "Shown — publish to apply" : "Hidden — publish to apply")}
                  />
                </span>
              </div>
            </li>
          ))}
        </ul>
      )}
      {editing ? <BannerDialog key={editing === "new" ? "new" : editing.id} row={editing === "new" ? null : editing} onClose={() => setEditing(null)} /> : null}
    </section>
  );
}

function BannerDialog({ row, onClose }: { row: BannerRow | null; onClose: () => void }) {
  const [d, setD] = useState<BannerInput>(draftOf(row));
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();
  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-h-[92vh] overflow-y-auto rounded-3xl sm:max-w-2xl">
        <DialogHeader>
          <DialogTitle>{row ? "Edit banner" : "Add banner"}</DialogTitle>
          <DialogDescription>Phone image 16:9; TV image wide (optional, falls back to the phone image).</DialogDescription>
        </DialogHeader>
        <div className="grid gap-4 sm:grid-cols-2">
          <div className="space-y-2">
            <Label>Phone image *</Label>
            <ImageUpload value={d.image_url || null} onChange={(url) => setD({ ...d, image_url: url ?? "" })} folder="banners" />
          </div>
          <div className="space-y-2">
            <Label>TV image</Label>
            <ImageUpload value={d.image_url_tv || null} onChange={(url) => setD({ ...d, image_url_tv: url ?? "" })} folder="banners" aspect="aspect-[21/9]" />
          </div>
          <div className="space-y-2">
            <Label>Title *</Label>
            <Input value={d.title} maxLength={100} onChange={(e) => setD({ ...d, title: e.target.value })} />
          </div>
          <div className="space-y-2">
            <Label>Subtitle</Label>
            <Input value={d.subtitle} maxLength={200} onChange={(e) => setD({ ...d, subtitle: e.target.value })} />
          </div>
          <div className="space-y-2">
            <Label>When tapped</Label>
            <select className={selectCls} value={d.action_type} onChange={(e) => setD({ ...d, action_type: e.target.value as BannerInput["action_type"] })}>
              {Object.entries(ACTIONS).map(([k, l]) => (
                <option key={k} value={k}>
                  {l}
                </option>
              ))}
            </select>
          </div>
          <div className="space-y-2">
            <Label>Button text</Label>
            <Input value={d.cta_label} maxLength={30} disabled={d.action_type === "none"} onChange={(e) => setD({ ...d, cta_label: e.target.value })} />
          </div>
          {d.action_type === "content" ? (
            <>
              <div className="space-y-2">
                <Label>Title type</Label>
                <select className={selectCls} value={d.item_kind} onChange={(e) => setD({ ...d, item_kind: e.target.value as BannerInput["item_kind"] })}>
                  <option value="movie">Movie</option>
                  <option value="series">Series</option>
                  <option value="live">Channel</option>
                </select>
              </div>
              <div className="space-y-2">
                <Label>TMDB id</Label>
                <Input inputMode="numeric" value={d.tmdb_id ?? ""} onChange={(e) => setD({ ...d, tmdb_id: e.target.value ? Number(e.target.value) || null : null })} placeholder="e.g. 157336" />
              </div>
              <div className="space-y-2">
                <Label>Panel item id (optional)</Label>
                <Input value={d.panel_item_id} maxLength={60} onChange={(e) => setD({ ...d, panel_item_id: e.target.value })} />
              </div>
              <div className="space-y-2">
                <Label>Panel key (for the id above)</Label>
                <Input value={d.panel_key} maxLength={30} placeholder="e.g. your provider's key" onChange={(e) => setD({ ...d, panel_key: e.target.value.toLowerCase() })} />
              </div>
            </>
          ) : d.action_type !== "none" ? (
            <div className="space-y-2 sm:col-span-2">
              <Label>{d.action_type === "url" ? "Link (https://…)" : d.action_type === "screen" ? "Screen (e.g. /sports, /live)" : "Category name"}</Label>
              <Input value={d.action_value} maxLength={300} onChange={(e) => setD({ ...d, action_value: e.target.value })} />
            </div>
          ) : null}
        </div>
        <TargetingFields value={d.targeting as Targeting} onChange={(t) => setD({ ...d, targeting: t })} />
        {error ? (
          <p role="alert" className="text-destructive text-sm">
            {error}
          </p>
        ) : null}
        <DialogFooter>
          <Button
            className="rounded-full"
            disabled={pending}
            onClick={() =>
              start(async () => {
                setError(null);
                const res = await saveBanner(row?.id ?? null, d);
                if (res.ok) {
                  toast.success("Banner saved — publish to apply");
                  onClose();
                } else setError(res.error);
              })
            }
          >
            {pending ? "Saving…" : "Save banner"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
