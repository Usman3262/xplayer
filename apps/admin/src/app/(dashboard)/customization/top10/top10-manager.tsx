"use client";

import { ArrowDown, ArrowUp, Pencil, Plus, Trash2 } from "lucide-react";
import { useState, useTransition } from "react";
import { toast } from "sonner";

import { EmptyState } from "@/components/states";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { cn } from "@/lib/utils";

import { deleteTop10List, saveTop10List, type Top10ItemInput, type Top10ListInput } from "./actions";

export type Top10Row = {
  id: string;
  title: string;
  content_kind: "mixed" | "movie" | "series";
  source: Top10ListInput["source"];
  params: { days?: number; min_rating?: number };
  country: string | null;
  is_enabled: boolean;
  top10_items: { rank: number; item_kind: "movie" | "series"; tmdb_id: number | null; match_title: string | null; panel_item_id: string | null; panel_key: string | null }[];
  used_by: number;
};

const SOURCE: Record<Top10ListInput["source"], string> = {
  provider_rating: "Best-rated in the user's panel",
  provider_added: "Newest in the user's panel",
  manual: "Your ranking",
  watch_stats: "Most watched on XPlayer (later)",
};
const KIND = { mixed: "Movies + series", movie: "Movies", series: "Series" } as const;
const selectCls = "bg-secondary/70 focus:ring-primary/40 h-10 w-full rounded-full px-4 text-sm outline-none focus:ring-2";

export function Top10Manager({ lists, canWrite }: { lists: Top10Row[]; canWrite: boolean }) {
  const [editing, setEditing] = useState<Top10Row | "new" | null>(null);
  const [pending, start] = useTransition();
  return (
    <section className="flex flex-col gap-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <p className="text-muted-foreground text-sm">Show a list on the home screen by adding a “Top 10” section in the Home builder and choosing the list.</p>
        {canWrite ? (
          <Button className="rounded-full" onClick={() => setEditing("new")}>
            <Plus /> New list
          </Button>
        ) : null}
      </div>
      {lists.length === 0 ? (
        <EmptyState title="No Top 10 lists" />
      ) : (
        <ul className="grid gap-4 lg:grid-cols-2">
          {lists.map((l) => (
            <li key={l.id} className={cn("bg-card/60 space-y-3 rounded-[28px] border p-5", !l.is_enabled && "opacity-55")}>
              <div className="flex items-start justify-between gap-3">
                <div className="min-w-0">
                  <p className="font-semibold">{l.title}</p>
                  <p className="text-muted-foreground text-sm">{SOURCE[l.source]}</p>
                </div>
                {canWrite ? (
                  <span className="flex gap-1">
                    <Button size="icon" variant="ghost" className="rounded-full" aria-label={`Edit ${l.title}`} onClick={() => setEditing(l)}>
                      <Pencil />
                    </Button>
                    <Button
                      size="icon"
                      variant="ghost"
                      className="text-destructive hover:text-destructive rounded-full"
                      aria-label={`Delete ${l.title}`}
                      disabled={pending}
                      onClick={() =>
                        window.confirm(l.used_by ? `“${l.title}” is used by ${l.used_by} home section(s); they'll lose their list. Delete?` : `Delete “${l.title}”?`) &&
                        start(async () => {
                          const res = await deleteTop10List(l.id);
                          if (res.ok) toast.success("Deleted — publish to apply");
                          else toast.error(res.error);
                        })
                      }
                    >
                      <Trash2 />
                    </Button>
                  </span>
                ) : null}
              </div>
              <div className="flex flex-wrap gap-1.5">
                <Badge className="bg-secondary text-foreground rounded-full font-normal">{KIND[l.content_kind]}</Badge>
                {l.params?.days ? <Badge className="bg-secondary text-muted-foreground rounded-full font-normal">last {l.params.days} days</Badge> : null}
                {l.params?.min_rating ? <Badge className="bg-secondary text-muted-foreground rounded-full font-normal">rating ≥ {l.params.min_rating}</Badge> : null}
                <Badge className="bg-secondary text-muted-foreground rounded-full font-normal">{l.country ?? "All countries"}</Badge>
                <Badge className={cn("rounded-full font-normal", l.used_by ? "bg-primary/15 text-primary" : "bg-secondary text-muted-foreground")}>
                  {l.used_by ? `on home (${l.used_by})` : "not on home"}
                </Badge>
              </div>
              {l.source === "manual" ? (
                <ol className="grid grid-cols-2 gap-x-4 gap-y-1 text-sm">
                  {l.top10_items.map((it) => (
                    <li key={it.rank} className="flex gap-2 truncate">
                      <span className="text-primary w-5 font-bold tabular-nums">{it.rank}</span>
                      <span className="truncate">{it.match_title || (it.tmdb_id ? `TMDB ${it.tmdb_id}` : `Panel ${it.panel_item_id}`)}</span>
                    </li>
                  ))}
                </ol>
              ) : null}
            </li>
          ))}
        </ul>
      )}
      {editing ? <Top10Dialog key={editing === "new" ? "new" : editing.id} row={editing === "new" ? null : editing} onClose={() => setEditing(null)} /> : null}
    </section>
  );
}

const emptyItem = (): Top10ItemInput => ({ item_kind: "movie", tmdb_id: null, match_title: "", panel_item_id: "", panel_key: "" });

function Top10Dialog({ row, onClose }: { row: Top10Row | null; onClose: () => void }) {
  const [d, setD] = useState<Top10ListInput>({
    title: row?.title ?? "Top 10 this week",
    content_kind: row?.content_kind ?? "mixed",
    source: row?.source ?? "provider_rating",
    days: row?.params?.days ?? 30,
    min_rating: row?.params?.min_rating ?? null,
    country: row?.country ?? "",
    is_enabled: row?.is_enabled ?? true,
  });
  const [items, setItems] = useState<Top10ItemInput[]>(
    row?.top10_items.map((it) => ({ item_kind: it.item_kind, tmdb_id: it.tmdb_id, match_title: it.match_title ?? "", panel_item_id: it.panel_item_id ?? "", panel_key: it.panel_key ?? "" })) ?? [],
  );
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();
  const move = (i: number, j: number) => setItems((xs) => {
    const c = [...xs];
    [c[i], c[j]] = [c[j], c[i]];
    return c;
  });

  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-h-[92vh] overflow-y-auto rounded-3xl sm:max-w-2xl">
        <DialogHeader>
          <DialogTitle>{row ? `Edit “${row.title}”` : "New Top 10 list"}</DialogTitle>
          <DialogDescription>Only titles the user&apos;s panel has are shown; the app fills the rest from the same rule.</DialogDescription>
        </DialogHeader>
        <div className="grid gap-4 sm:grid-cols-2">
          <div className="space-y-2">
            <Label>Title</Label>
            <Input value={d.title} maxLength={80} onChange={(e) => setD({ ...d, title: e.target.value })} />
          </div>
          <div className="space-y-2">
            <Label>Ranking from</Label>
            <select className={selectCls} value={d.source} onChange={(e) => setD({ ...d, source: e.target.value as Top10ListInput["source"] })}>
              {Object.entries(SOURCE).map(([k, l]) => (
                <option key={k} value={k}>
                  {l}
                </option>
              ))}
            </select>
          </div>
          <div className="space-y-2">
            <Label>Shows</Label>
            <select className={selectCls} value={d.content_kind} onChange={(e) => setD({ ...d, content_kind: e.target.value as Top10ListInput["content_kind"] })}>
              {Object.entries(KIND).map(([k, l]) => (
                <option key={k} value={k}>
                  {l}
                </option>
              ))}
            </select>
          </div>
          <div className="space-y-2">
            <Label>Country (optional)</Label>
            <Input value={d.country} maxLength={2} placeholder="All countries" onChange={(e) => setD({ ...d, country: e.target.value.toUpperCase() })} />
          </div>
          {d.source === "provider_rating" || d.source === "provider_added" ? (
            <div className="space-y-2">
              <Label>Only titles added in the last … days</Label>
              <Input type="number" min={1} max={365} value={d.days ?? ""} placeholder="any time" onChange={(e) => setD({ ...d, days: e.target.value ? Number(e.target.value) : null })} />
            </div>
          ) : null}
          {d.source === "provider_rating" ? (
            <div className="space-y-2">
              <Label>Minimum rating</Label>
              <Input type="number" min={0} max={10} step={0.5} value={d.min_rating ?? ""} placeholder="none" onChange={(e) => setD({ ...d, min_rating: e.target.value ? Number(e.target.value) : null })} />
            </div>
          ) : null}
          <label className="bg-secondary/40 flex items-center justify-between gap-3 rounded-2xl px-4 py-3 sm:col-span-2">
            <span className="text-sm">List is active</span>
            <Switch checked={d.is_enabled} onCheckedChange={(v) => setD({ ...d, is_enabled: v })} />
          </label>
        </div>

        {d.source === "manual" ? (
          <fieldset className="space-y-2">
            <div className="flex items-center justify-between">
              <legend className="text-sm font-medium">Your ranking ({items.length}/10)</legend>
              <Button type="button" size="sm" variant="outline" className="rounded-full" disabled={items.length >= 10} onClick={() => setItems([...items, emptyItem()])}>
                <Plus /> Add title
              </Button>
            </div>
            {items.map((it, i) => (
              <div key={i} className="bg-secondary/40 grid items-center gap-2 rounded-2xl p-2 sm:grid-cols-[28px_100px_1fr_100px_auto]">
                <span className="text-primary text-center text-lg font-bold tabular-nums">{i + 1}</span>
                <select className={selectCls} value={it.item_kind} onChange={(e) => setItems(items.map((x, j) => (j === i ? { ...x, item_kind: e.target.value as "movie" | "series" } : x)))} aria-label="Type">
                  <option value="movie">Movie</option>
                  <option value="series">Series</option>
                </select>
                <Input placeholder="Title to match" value={it.match_title} onChange={(e) => setItems(items.map((x, j) => (j === i ? { ...x, match_title: e.target.value } : x)))} />
                <Input placeholder="TMDB id" inputMode="numeric" value={it.tmdb_id ?? ""} onChange={(e) => setItems(items.map((x, j) => (j === i ? { ...x, tmdb_id: e.target.value ? Number(e.target.value) || null : null } : x)))} />
                <span className="flex">
                  <Button type="button" size="icon" variant="ghost" className="rounded-full" disabled={i === 0} aria-label="Up" onClick={() => move(i, i - 1)}>
                    <ArrowUp />
                  </Button>
                  <Button type="button" size="icon" variant="ghost" className="rounded-full" disabled={i === items.length - 1} aria-label="Down" onClick={() => move(i, i + 1)}>
                    <ArrowDown />
                  </Button>
                  <Button type="button" size="icon" variant="ghost" className="text-destructive rounded-full" aria-label="Remove" onClick={() => setItems(items.filter((_, j) => j !== i))}>
                    <Trash2 />
                  </Button>
                </span>
              </div>
            ))}
          </fieldset>
        ) : null}

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
                const res = await saveTop10List(row?.id ?? null, d, items);
                if (res.ok) {
                  toast.success("Saved — publish to apply");
                  onClose();
                } else setError(res.error);
              })
            }
          >
            {pending ? "Saving…" : "Save list"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
