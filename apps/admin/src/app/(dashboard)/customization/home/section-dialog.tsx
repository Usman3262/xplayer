"use client";

import { Plus, Trash2 } from "lucide-react";
import { useState, useTransition } from "react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { ITEM_KINDS, KINDS, LAYOUTS, SECTION_TYPES, SOURCE_PARAMS, SOURCES, type SourceKey } from "@/lib/home-sections";

import { createSection, setSectionItems, updateSection, type ItemInput, type SectionInput } from "./actions";

export type SectionItem = {
  item_kind: "movie" | "series" | "live" | "link";
  tmdb_id: number | null;
  match_title: string | null;
  panel_item_id: string | null;
  panel_key: string | null;
  title: string | null;
  image_url: string | null;
  deep_link: string | null;
};

export type SectionRow = {
  id: string;
  title: string;
  subtitle: string | null;
  section_type: string;
  content_kind: string | null;
  source: string;
  layout: string;
  item_limit: number;
  params: { days?: number; match?: string; min_rating?: number };
  platforms: string[] | null;
  countries: string[] | null;
  requires_login: boolean;
  starts_at: string | null;
  ends_at: string | null;
  is_enabled: boolean;
  home_section_items: SectionItem[];
};

const selectCls = "bg-secondary/70 focus:ring-primary/40 h-10 w-full rounded-full px-4 text-sm outline-none focus:ring-2";

function toLocalInput(iso: string | null): string {
  if (!iso) return "";
  const d = new Date(iso);
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

const emptyDraft = (type = "custom"): SectionInput => {
  const def = SECTION_TYPES[type];
  return {
    title: def.label,
    subtitle: "",
    section_type: type,
    content_kind: def.kinds[0],
    source: def.sources[0],
    layout: def.layouts[0],
    item_limit: 20,
    params: {},
    platforms: [],
    countries: [],
    requires_login: false,
    starts_at: "",
    ends_at: "",
  };
};

const fromRow = (r: SectionRow): SectionInput => ({
  title: r.title,
  subtitle: r.subtitle ?? "",
  section_type: r.section_type,
  content_kind: r.content_kind ?? SECTION_TYPES[r.section_type]?.kinds[0] ?? "mixed",
  source: r.source,
  layout: r.layout,
  item_limit: r.item_limit,
  params: r.params ?? {},
  platforms: (r.platforms ?? []) as SectionInput["platforms"],
  countries: r.countries ?? [],
  requires_login: r.requires_login,
  starts_at: toLocalInput(r.starts_at),
  ends_at: toLocalInput(r.ends_at),
});

const emptyItem = (): SectionItem => ({ item_kind: "movie", tmdb_id: null, match_title: "", panel_item_id: "", panel_key: "", title: "", image_url: "", deep_link: "" });

/** Create (row = null) or edit a section, including manual picks. */
export function SectionDialog({ open, onOpenChange, row }: { open: boolean; onOpenChange: (o: boolean) => void; row: SectionRow | null }) {
  const [d, setD] = useState<SectionInput>(row ? fromRow(row) : emptyDraft());
  const [items, setItems] = useState<SectionItem[]>(row?.home_section_items ?? []);
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();
  const def = SECTION_TYPES[d.section_type] ?? SECTION_TYPES.custom;
  const paramKeys = SOURCE_PARAMS[d.source as SourceKey] ?? [];

  const changeType = (type: string) => {
    const nd = SECTION_TYPES[type];
    setD({
      ...d,
      section_type: type,
      title: d.title === def.label ? nd.label : d.title,
      source: nd.sources.includes(d.source as never) ? d.source : nd.sources[0],
      layout: nd.layouts.includes(d.layout as never) ? d.layout : nd.layouts[0],
      content_kind: nd.kinds.includes(d.content_kind as never) ? d.content_kind : nd.kinds[0],
    });
  };

  const save = () =>
    start(async () => {
      setError(null);
      const res = row ? await updateSection(row.id, d) : await createSection(d);
      if (!res.ok) return setError(res.error);
      const id = row?.id ?? (res.data as { id: string } | undefined)?.id;
      if (id && d.source === "manual") {
        const ir = await setSectionItems(
          id,
          items.map<ItemInput>((it) => ({
            item_kind: it.item_kind,
            tmdb_id: it.tmdb_id,
            match_title: it.match_title ?? "",
            panel_item_id: it.panel_item_id ?? "",
            panel_key: it.panel_key ?? "",
            title: it.title ?? "",
            image_url: it.image_url ?? "",
            deep_link: it.deep_link ?? "",
          })),
        );
        if (!ir.ok) return setError(ir.error);
      }
      toast.success(row ? "Section saved — publish to apply" : "Section added — publish to apply");
      onOpenChange(false);
    });

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-h-[92vh] overflow-y-auto rounded-3xl sm:max-w-2xl">
        <DialogHeader>
          <DialogTitle>{row ? `Edit “${row.title}”` : "Add section"}</DialogTitle>
          <DialogDescription>{def.hint}</DialogDescription>
        </DialogHeader>

        <div className="grid gap-4 sm:grid-cols-2">
          <div className="space-y-2">
            <Label>Section type</Label>
            <select className={selectCls} value={d.section_type} onChange={(e) => changeType(e.target.value)}>
              {Object.entries(SECTION_TYPES).map(([k, t]) => (
                <option key={k} value={k}>
                  {t.label}
                </option>
              ))}
            </select>
          </div>
          <div className="space-y-2">
            <Label>Title</Label>
            <Input value={d.title} maxLength={80} onChange={(e) => setD({ ...d, title: e.target.value })} />
          </div>
          <div className="space-y-2">
            <Label>Content from</Label>
            <select className={selectCls} value={d.source} onChange={(e) => setD({ ...d, source: e.target.value })}>
              {def.sources.map((s) => (
                <option key={s} value={s}>
                  {SOURCES[s].label}
                </option>
              ))}
            </select>
            <p className="text-muted-foreground text-xs">{SOURCES[d.source as SourceKey]?.hint}</p>
          </div>
          <div className="space-y-2">
            <Label>Shows</Label>
            <select className={selectCls} value={d.content_kind} onChange={(e) => setD({ ...d, content_kind: e.target.value })}>
              {def.kinds.map((k) => (
                <option key={k} value={k}>
                  {KINDS[k]}
                </option>
              ))}
            </select>
          </div>
          <div className="space-y-2">
            <Label>Layout</Label>
            <select className={selectCls} value={d.layout} onChange={(e) => setD({ ...d, layout: e.target.value })}>
              {def.layouts.map((l) => (
                <option key={l} value={l}>
                  {LAYOUTS[l]}
                </option>
              ))}
            </select>
          </div>
          <div className="space-y-2">
            <Label>Max items</Label>
            <Input type="number" min={1} max={100} value={d.item_limit} onChange={(e) => setD({ ...d, item_limit: Number(e.target.value) })} />
          </div>
          {paramKeys.includes("days") ? (
            <div className="space-y-2">
              <Label>Only titles from the last … days</Label>
              <Input type="number" min={1} max={365} placeholder="any time" value={d.params.days ?? ""} onChange={(e) => setD({ ...d, params: { ...d.params, days: e.target.value ? Number(e.target.value) : undefined } })} />
            </div>
          ) : null}
          {paramKeys.includes("min_rating") ? (
            <div className="space-y-2">
              <Label>Minimum rating (0–10)</Label>
              <Input type="number" min={0} max={10} step={0.5} placeholder="none" value={d.params.min_rating ?? ""} onChange={(e) => setD({ ...d, params: { ...d.params, min_rating: e.target.value ? Number(e.target.value) : undefined } })} />
            </div>
          ) : null}
          {paramKeys.includes("match") ? (
            <div className="space-y-2 sm:col-span-2">
              <Label>Panel category name contains</Label>
              <Input placeholder="e.g. Netflix, Kids, Sports" maxLength={80} value={d.params.match ?? ""} onChange={(e) => setD({ ...d, params: { ...d.params, match: e.target.value } })} />
            </div>
          ) : null}
        </div>

        {d.source === "manual" ? (
          <fieldset className="space-y-3">
            <div className="flex items-center justify-between">
              <legend className="text-sm font-medium">Your picks ({items.length})</legend>
              <Button type="button" size="sm" variant="outline" className="rounded-full" onClick={() => setItems([...items, emptyItem()])}>
                <Plus /> Add pick
              </Button>
            </div>
            <p className="text-muted-foreground text-xs">Matched against each user&apos;s own panel (panel id → TMDB id → title). Hidden if the panel doesn&apos;t have it.</p>
            {items.map((it, i) => (
              <div key={i} className="bg-secondary/40 grid gap-2 rounded-2xl p-3 sm:grid-cols-[110px_1fr_110px_auto]">
                <select className={selectCls} value={it.item_kind} onChange={(e) => setItems(items.map((x, j) => (j === i ? { ...x, item_kind: e.target.value as SectionItem["item_kind"] } : x)))} aria-label="Kind">
                  {Object.entries(ITEM_KINDS).map(([k, l]) => (
                    <option key={k} value={k}>
                      {l}
                    </option>
                  ))}
                </select>
                {it.item_kind === "link" ? (
                  <Input placeholder="Link (screen route or https URL)" value={it.deep_link ?? ""} onChange={(e) => setItems(items.map((x, j) => (j === i ? { ...x, deep_link: e.target.value } : x)))} />
                ) : (
                  <Input placeholder="Title to match, e.g. Interstellar" value={it.match_title ?? ""} onChange={(e) => setItems(items.map((x, j) => (j === i ? { ...x, match_title: e.target.value } : x)))} />
                )}
                <Input placeholder="TMDB id" inputMode="numeric" value={it.tmdb_id ?? ""} onChange={(e) => setItems(items.map((x, j) => (j === i ? { ...x, tmdb_id: e.target.value ? Number(e.target.value) || null : null } : x)))} disabled={it.item_kind === "link" || it.item_kind === "live"} />
                <Button type="button" size="icon" variant="ghost" className="text-destructive rounded-full" aria-label="Remove pick" onClick={() => setItems(items.filter((_, j) => j !== i))}>
                  <Trash2 />
                </Button>
              </div>
            ))}
          </fieldset>
        ) : null}

        <fieldset className="space-y-3">
          <legend className="text-sm font-medium">Who sees it</legend>
          <div className="flex flex-wrap gap-2">
            {(["android", "ios", "tv"] as const).map((k) => {
              const on = d.platforms.length === 0 || d.platforms.includes(k);
              return (
                <button
                  key={k}
                  type="button"
                  onClick={() => {
                    const cur = d.platforms.length === 0 ? ["android", "ios", "tv"] : d.platforms;
                    const next = on ? cur.filter((x) => x !== k) : [...cur, k];
                    setD({ ...d, platforms: next.length === 3 ? [] : (next as SectionInput["platforms"]) });
                  }}
                  className={on ? "bg-primary/15 text-primary rounded-full px-4 py-2 text-sm" : "bg-secondary/70 text-muted-foreground rounded-full px-4 py-2 text-sm"}
                >
                  {k === "ios" ? "iPhone" : k === "tv" ? "Android TV" : "Android phone"}
                </button>
              );
            })}
          </div>
          <div className="grid gap-4 sm:grid-cols-2">
            <div className="space-y-2">
              <Label>Countries (optional)</Label>
              <Input
                placeholder="All — or e.g. PK, AE, GB"
                value={d.countries.join(", ")}
                onChange={(e) => setD({ ...d, countries: e.target.value.toUpperCase().split(/[\s,]+/).filter(Boolean) })}
              />
            </div>
            <label className="bg-secondary/40 flex items-center justify-between gap-3 rounded-2xl px-4">
              <span className="text-sm">Only signed-in users</span>
              <Switch checked={d.requires_login} onCheckedChange={(v) => setD({ ...d, requires_login: v })} />
            </label>
            <div className="space-y-2">
              <Label>Show from</Label>
              <Input type="datetime-local" value={d.starts_at} onChange={(e) => setD({ ...d, starts_at: e.target.value })} />
            </div>
            <div className="space-y-2">
              <Label>Show until</Label>
              <Input type="datetime-local" value={d.ends_at} onChange={(e) => setD({ ...d, ends_at: e.target.value })} />
            </div>
          </div>
        </fieldset>

        {error ? (
          <p role="alert" className="text-destructive text-sm">
            {error}
          </p>
        ) : null}
        <DialogFooter>
          <Button className="rounded-full" disabled={pending} onClick={save}>
            {pending ? "Saving…" : row ? "Save section" : "Add section"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
