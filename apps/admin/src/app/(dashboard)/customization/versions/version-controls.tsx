"use client";

import { Plus, Smartphone, Trash2, Tv } from "lucide-react";
import { useState, useTransition } from "react";
import { toast } from "sonner";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { Textarea } from "@/components/ui/textarea";
import { cn } from "@/lib/utils";

import { createMaintenance, deleteMaintenance, saveAppVersion, setMaintenanceActive } from "./actions";

export type VersionRow = {
  platform: "android" | "ios" | "tv";
  min_version: string;
  recommended_version: string | null;
  latest_version: string | null;
  update_url: string | null;
  release_notes: string | null;
};

export type MaintenanceRow = {
  id: string;
  title: string;
  message: string;
  platforms: string[] | null;
  starts_at: string;
  ends_at: string;
  is_active: boolean;
};

const PLATFORM_LABEL = { android: "Android phone", ios: "iPhone", tv: "Android TV" } as const;
const fmt = (iso: string) => new Intl.DateTimeFormat("en", { dateStyle: "medium", timeStyle: "short" }).format(new Date(iso));

export function VersionCard({ row, canWrite }: { row: VersionRow; canWrite: boolean }) {
  const [pending, start] = useTransition();
  const Icon = row.platform === "tv" ? Tv : Smartphone;
  return (
    <form
      className="bg-card/60 space-y-4 rounded-[28px] border p-6"
      onSubmit={(e) => {
        e.preventDefault();
        const fd = new FormData(e.currentTarget);
        start(async () => {
          const res = await saveAppVersion({
            platform: row.platform,
            min_version: String(fd.get("min") ?? ""),
            recommended_version: String(fd.get("rec") ?? ""),
            latest_version: String(fd.get("latest") ?? ""),
            update_url: String(fd.get("url") ?? ""),
            release_notes: String(fd.get("notes") ?? ""),
          });
          if (res.ok) toast.success(`${PLATFORM_LABEL[row.platform]} saved — publish to apply`);
          else toast.error(res.error);
        });
      }}
    >
      <div className="flex items-center gap-3">
        <span className="bg-primary/15 text-primary flex size-10 items-center justify-center rounded-xl">
          <Icon className="size-5" />
        </span>
        <h3 className="font-semibold">{PLATFORM_LABEL[row.platform]}</h3>
      </div>
      <div className="grid grid-cols-3 gap-3">
        <div className="space-y-1.5">
          <Label className="text-xs">Minimum</Label>
          <Input name="min" defaultValue={row.min_version === "0.0.0" ? "" : row.min_version} placeholder="none" disabled={!canWrite} />
        </div>
        <div className="space-y-1.5">
          <Label className="text-xs">Recommended</Label>
          <Input name="rec" defaultValue={row.recommended_version ?? ""} placeholder="none" disabled={!canWrite} />
        </div>
        <div className="space-y-1.5">
          <Label className="text-xs">Latest</Label>
          <Input name="latest" defaultValue={row.latest_version ?? ""} placeholder="none" disabled={!canWrite} />
        </div>
      </div>
      <p className="text-muted-foreground text-xs">Below minimum = must update. Below recommended = update suggested.</p>
      <div className="space-y-1.5">
        <Label className="text-xs">Update link</Label>
        <Input name="url" defaultValue={row.update_url ?? ""} placeholder="https://… (store page or download)" disabled={!canWrite} />
      </div>
      <div className="space-y-1.5">
        <Label className="text-xs">What&apos;s new</Label>
        <Textarea name="notes" defaultValue={row.release_notes ?? ""} rows={2} maxLength={1000} disabled={!canWrite} />
      </div>
      {canWrite ? (
        <Button type="submit" className="rounded-full" disabled={pending}>
          {pending ? "Saving…" : "Save"}
        </Button>
      ) : null}
    </form>
  );
}

export function MaintenanceList({ rows, canWrite, now }: { rows: MaintenanceRow[]; canWrite: boolean; now: number }) {
  const [pending, start] = useTransition();
  const run = (fn: () => Promise<{ ok: boolean; error?: string }>, ok: string) =>
    start(async () => {
      const res = await fn();
      if (res.ok) toast.success(ok);
      else toast.error(res.error ?? "Failed");
    });

  return (
    <section className="bg-card/60 space-y-4 rounded-[28px] border p-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h2 className="font-semibold">Maintenance</h2>
          <p className="text-muted-foreground text-sm">During a window the apps show your message instead of content.</p>
        </div>
        {canWrite ? <NewMaintenanceDialog /> : null}
      </div>
      {rows.length === 0 ? (
        <p className="text-muted-foreground rounded-2xl border border-dashed p-6 text-center text-sm">No maintenance planned.</p>
      ) : (
        <ul className="space-y-3">
          {rows.map((m) => {
            const s = Date.parse(m.starts_at);
            const e = Date.parse(m.ends_at);
            const state = !m.is_active ? "Off" : now >= e ? "Finished" : now >= s ? "Now" : "Scheduled";
            return (
              <li key={m.id} className={cn("bg-secondary/40 flex flex-wrap items-center gap-3 rounded-2xl p-4", state === "Finished" && "opacity-60")}>
                <div className="min-w-0 flex-1">
                  <p className="flex items-center gap-2 text-sm font-medium">
                    {m.title}
                    <Badge
                      className={cn(
                        "rounded-full",
                        state === "Now" ? "bg-primary text-primary-foreground" : state === "Scheduled" ? "bg-amber-500/15 text-amber-300" : "bg-secondary text-muted-foreground",
                      )}
                    >
                      {state}
                    </Badge>
                  </p>
                  <p className="text-muted-foreground truncate text-xs">{m.message}</p>
                  <p className="text-muted-foreground text-xs">
                    {fmt(m.starts_at)} → {fmt(m.ends_at)} · {m.platforms?.length ? m.platforms.join(", ") : "all platforms"}
                  </p>
                </div>
                {canWrite ? (
                  <>
                    <Switch
                      checked={m.is_active}
                      disabled={pending}
                      aria-label={`${m.title} active`}
                      onCheckedChange={(v) => run(() => setMaintenanceActive(m.id, v), v ? "Activated — publish to apply" : "Turned off — publish to apply")}
                    />
                    <Button
                      size="icon"
                      variant="ghost"
                      className="text-destructive hover:text-destructive rounded-full"
                      aria-label={`Delete ${m.title}`}
                      disabled={pending}
                      onClick={() => {
                        if (window.confirm(`Delete “${m.title}”?`)) run(() => deleteMaintenance(m.id), "Deleted — publish to apply");
                      }}
                    >
                      <Trash2 />
                    </Button>
                  </>
                ) : null}
              </li>
            );
          })}
        </ul>
      )}
    </section>
  );
}

function NewMaintenanceDialog() {
  const [open, setOpen] = useState(false);
  const [pending, start] = useTransition();
  const [error, setError] = useState<string | null>(null);
  return (
    <Dialog open={open} onOpenChange={(o) => { setOpen(o); setError(null); }}>
      <DialogTrigger render={<Button className="rounded-full" />}>
        <Plus /> Schedule maintenance
      </DialogTrigger>
      <DialogContent className="rounded-3xl sm:max-w-lg">
        <form
          className="space-y-4"
          onSubmit={(e) => {
            e.preventDefault();
            const fd = new FormData(e.currentTarget);
            setError(null);
            start(async () => {
              const res = await createMaintenance({
                title: String(fd.get("title") ?? ""),
                message: String(fd.get("message") ?? ""),
                platforms: (["android", "ios", "tv"] as const).filter((k) => fd.get(`p_${k}`) === "on"),
                starts_at: String(fd.get("from") ?? ""),
                ends_at: String(fd.get("to") ?? ""),
              });
              if (res.ok) {
                toast.success("Scheduled — publish to send it to the apps");
                setOpen(false);
              } else setError(res.error);
            });
          }}
        >
          <DialogHeader>
            <DialogTitle>Schedule maintenance</DialogTitle>
            <DialogDescription>Users see this message instead of the app during the window.</DialogDescription>
          </DialogHeader>
          <div className="space-y-2">
            <Label htmlFor="m-title">Title</Label>
            <Input id="m-title" name="title" maxLength={80} placeholder="We'll be right back" required />
          </div>
          <div className="space-y-2">
            <Label htmlFor="m-msg">Message</Label>
            <Textarea id="m-msg" name="message" maxLength={500} rows={3} required placeholder="We're improving XPlayer. Please try again at 18:00." />
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-2">
              <Label htmlFor="m-from">Starts</Label>
              <Input id="m-from" name="from" type="datetime-local" required />
            </div>
            <div className="space-y-2">
              <Label htmlFor="m-to">Ends</Label>
              <Input id="m-to" name="to" type="datetime-local" required />
            </div>
          </div>
          <fieldset className="flex flex-wrap gap-2">
            {(["android", "ios", "tv"] as const).map((k) => (
              <label key={k} className="bg-secondary/70 has-checked:bg-primary/15 has-checked:text-primary flex cursor-pointer items-center gap-2 rounded-full px-4 py-2 text-sm">
                <input type="checkbox" name={`p_${k}`} defaultChecked className="accent-[var(--primary)]" />
                {PLATFORM_LABEL[k]}
              </label>
            ))}
          </fieldset>
          {error ? (
            <p role="alert" className="text-destructive text-sm">
              {error}
            </p>
          ) : null}
          <DialogFooter>
            <Button type="submit" className="rounded-full" disabled={pending}>
              {pending ? "Saving…" : "Schedule"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
