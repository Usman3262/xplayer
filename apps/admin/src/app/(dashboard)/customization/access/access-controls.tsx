"use client";

import { ArrowDown, ArrowUp, ChevronRight, Pencil, Router, Server, ListVideo } from "lucide-react";
import { useState, useTransition } from "react";
import { toast } from "sonner";

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

import { movePanel, saveSignInPolicy, setPanelEnabled, updatePanel } from "./actions";

export type Policy = {
  mode: "optional" | "required" | "disabled";
  allow_registration: boolean;
  guest_enabled: boolean;
  max_connections: number;
  connect_timeout_s: number;
};

export type PanelField = { key: string; type: string; label: string; placeholder?: string; required?: boolean };
export type PanelType = {
  key: string;
  label: string;
  description: string | null;
  help_text: string | null;
  icon: string | null;
  is_enabled: boolean;
  platforms: string[] | null;
  fields: PanelField[];
};

const MODES = [
  { key: "optional", title: "Optional", text: "Use the app as a guest; sign in to sync across devices." },
  { key: "required", title: "Required", text: "Everyone must sign in before using the app." },
  { key: "disabled", title: "Off", text: "No accounts at all — everything stays on the device." },
] as const;

export function SignInPolicyForm({ initial, canWrite }: { initial: Policy; canWrite: boolean }) {
  const [p, setP] = useState(initial);
  const [pending, start] = useTransition();
  const dirty = JSON.stringify(p) !== JSON.stringify(initial);
  const guestLocked = p.mode !== "optional";
  const regLocked = p.mode === "disabled";

  return (
    <section className="bg-card/60 space-y-5 rounded-[28px] border p-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h2 className="font-semibold">Sign-in</h2>
          <p className="text-muted-foreground text-sm">How people use accounts in the apps.</p>
        </div>
        <Button
          className="rounded-full"
          disabled={!canWrite || !dirty || pending}
          onClick={() =>
            start(async () => {
              const res = await saveSignInPolicy(p);
              if (res.ok) toast.success("Saved — publish to send it to the apps");
              else toast.error(res.error);
            })
          }
        >
          {pending ? "Saving…" : "Save"}
        </Button>
      </div>

      <div className="grid gap-3 md:grid-cols-3">
        {MODES.map((m) => (
          <button
            key={m.key}
            type="button"
            disabled={!canWrite}
            onClick={() =>
              setP({
                ...p,
                mode: m.key,
                guest_enabled: m.key === "required" ? false : true,
                allow_registration: m.key === "disabled" ? false : p.allow_registration,
              })
            }
            className={cn(
              "rounded-2xl border p-4 text-left transition-colors disabled:opacity-60",
              p.mode === m.key ? "border-primary bg-primary/10" : "hover:bg-secondary/50",
            )}
          >
            <p className={cn("font-medium", p.mode === m.key && "text-primary")}>{m.title}</p>
            <p className="text-muted-foreground mt-1 text-xs">{m.text}</p>
          </button>
        ))}
      </div>

      <div className="grid gap-4 md:grid-cols-2">
        <label className="bg-secondary/40 flex items-center justify-between gap-3 rounded-2xl p-4">
          <span>
            <span className="block text-sm font-medium">Guest use</span>
            <span className="text-muted-foreground block text-xs">
              {guestLocked ? (p.mode === "required" ? "Off because sign-in is required" : "Always on when accounts are off") : "Use the app without an account"}
            </span>
          </span>
          <Switch checked={p.guest_enabled} disabled={!canWrite || guestLocked} onCheckedChange={(v) => setP({ ...p, guest_enabled: v })} />
        </label>
        <label className="bg-secondary/40 flex items-center justify-between gap-3 rounded-2xl p-4">
          <span>
            <span className="block text-sm font-medium">New sign-ups</span>
            <span className="text-muted-foreground block text-xs">{regLocked ? "Off because accounts are off" : "Let people create accounts"}</span>
          </span>
          <Switch checked={p.allow_registration} disabled={!canWrite || regLocked} onCheckedChange={(v) => setP({ ...p, allow_registration: v })} />
        </label>
        <div className="space-y-2">
          <Label htmlFor="max-panels">Panels per user</Label>
          <Input
            id="max-panels"
            type="number"
            min={1}
            max={50}
            value={p.max_connections}
            disabled={!canWrite}
            onChange={(e) => setP({ ...p, max_connections: Number(e.target.value) })}
          />
        </div>
        <div className="space-y-2">
          <Label htmlFor="timeout">Connect timeout (seconds)</Label>
          <Input
            id="timeout"
            type="number"
            min={1}
            max={60}
            value={p.connect_timeout_s}
            disabled={!canWrite}
            onChange={(e) => setP({ ...p, connect_timeout_s: Number(e.target.value) })}
          />
        </div>
      </div>
    </section>
  );
}

const ICONS: Record<string, typeof Server> = { dns: Server, playlist_play: ListVideo, router: Router };
const iconFor = (k: string | null) => ICONS[k ?? ""] ?? Server;

export function PanelList({ panels, canWrite }: { panels: PanelType[]; canWrite: boolean }) {
  const [pending, start] = useTransition();
  const [preview, setPreview] = useState<string>(panels.find((p) => p.is_enabled)?.key ?? panels[0]?.key ?? "");
  const shown = panels.find((p) => p.key === preview);

  const run = (fn: () => Promise<{ ok: boolean; error?: string }>, ok: string) =>
    start(async () => {
      const res = await fn();
      if (res.ok) toast.success(ok);
      else toast.error(res.error ?? "Failed");
    });

  return (
    <div className="grid gap-8 xl:grid-cols-[minmax(0,1fr)_auto]">
      <section className="bg-card/60 space-y-4 rounded-[28px] border p-6">
        <div>
          <h2 className="font-semibold">“Choose your panel”</h2>
          <p className="text-muted-foreground text-sm">The first screen after the splash: which connection types users can pick, in this order.</p>
        </div>
        <ul className="space-y-3">
          {panels.map((p, i) => {
            const Icon = iconFor(p.icon);
            return (
              <li key={p.key} className={cn("bg-secondary/40 flex items-center gap-3 rounded-2xl p-3", !p.is_enabled && "opacity-60")}>
                <span className="bg-primary/15 text-primary flex size-10 shrink-0 items-center justify-center rounded-xl">
                  <Icon className="size-5" />
                </span>
                <button type="button" onClick={() => setPreview(p.key)} className="min-w-0 flex-1 text-left">
                  <span className="block truncate text-sm font-medium">{p.label}</span>
                  <span className="text-muted-foreground block truncate text-xs">
                    {p.description} · {p.platforms?.length ? p.platforms.join(", ") : "all platforms"}
                  </span>
                </button>
                {canWrite ? (
                  <>
                    <Button size="icon" variant="ghost" className="rounded-full" disabled={pending || i === 0} aria-label={`Move ${p.label} up`} onClick={() => run(() => movePanel(p.key, "up"), "Order saved")}>
                      <ArrowUp />
                    </Button>
                    <Button size="icon" variant="ghost" className="rounded-full" disabled={pending || i === panels.length - 1} aria-label={`Move ${p.label} down`} onClick={() => run(() => movePanel(p.key, "down"), "Order saved")}>
                      <ArrowDown />
                    </Button>
                    <PanelEditDialog panel={p} />
                  </>
                ) : null}
                <Switch
                  checked={p.is_enabled}
                  disabled={!canWrite || pending}
                  aria-label={`${p.label} ${p.is_enabled ? "on" : "off"}`}
                  onCheckedChange={(v) => run(() => setPanelEnabled(p.key, v), `${p.label} ${v ? "on" : "off"} — publish to apply`)}
                />
              </li>
            );
          })}
        </ul>
      </section>

      <aside className="flex flex-col items-center gap-3">
        <p className="text-muted-foreground text-xs tracking-wide uppercase">Preview</p>
        <ChooseYourPanelPreview panels={panels.filter((p) => p.is_enabled)} selected={shown?.is_enabled ? shown : undefined} />
      </aside>
    </div>
  );
}

function ChooseYourPanelPreview({ panels, selected }: { panels: PanelType[]; selected?: PanelType }) {
  return (
    <div className="w-[250px] rounded-[38px] border-[6px] border-black bg-black shadow-2xl">
      <div className="h-[500px] overflow-hidden rounded-[32px] bg-[#0D0607] px-4 pt-6 text-white">
        <p className="text-center text-sm font-semibold">Choose your panel</p>
        <div className="mt-4 space-y-2">
          {panels.map((p) => {
            const Icon = iconFor(p.icon);
            return (
              <div key={p.key} className={cn("flex items-center gap-3 rounded-2xl p-3", selected?.key === p.key ? "bg-[#E11D2E]" : "bg-[#1A0B0D]")}>
                <Icon className="size-5 shrink-0" />
                <div className="min-w-0 flex-1">
                  <p className="truncate text-xs font-semibold">{p.label}</p>
                  <p className="truncate text-[10px] opacity-70">{p.description}</p>
                </div>
                <ChevronRight className="size-4 opacity-60" />
              </div>
            );
          })}
        </div>
        {selected ? (
          <div className="mt-5 space-y-2">
            {selected.fields.map((f) => (
              <div key={f.key}>
                <p className="text-[10px] opacity-70">
                  {f.label}
                  {f.required ? " *" : ""}
                </p>
                <div className="mt-0.5 truncate rounded-lg bg-[#2A1013] px-2 py-1.5 text-[10px] opacity-60">
                  {f.type === "password" ? "••••••" : f.placeholder || " "}
                </div>
              </div>
            ))}
            <div className="mt-3 rounded-xl bg-[#E11D2E] py-2 text-center text-xs font-semibold">Connect</div>
            {selected.help_text ? <p className="text-[9px] leading-snug opacity-60">{selected.help_text}</p> : null}
          </div>
        ) : null}
      </div>
    </div>
  );
}

function PanelEditDialog({ panel }: { panel: PanelType }) {
  const [open, setOpen] = useState(false);
  const [pending, start] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const all = !panel.platforms?.length;
  return (
    <Dialog open={open} onOpenChange={(o) => { setOpen(o); setError(null); }}>
      <DialogTrigger render={<Button size="icon" variant="ghost" className="rounded-full" aria-label={`Edit ${panel.label}`} />}>
        <Pencil />
      </DialogTrigger>
      <DialogContent className="max-h-[90vh] overflow-y-auto rounded-3xl sm:max-w-lg">
        <form
          className="space-y-5"
          onSubmit={(e) => {
            e.preventDefault();
            const fd = new FormData(e.currentTarget);
            setError(null);
            start(async () => {
              const res = await updatePanel({
                key: panel.key,
                label: String(fd.get("label") ?? ""),
                description: String(fd.get("description") ?? ""),
                help_text: String(fd.get("help") ?? ""),
                platforms: (["android", "ios", "tv"] as const).filter((k) => fd.get(`p_${k}`) === "on"),
                fields: panel.fields.map((f) => ({
                  key: f.key,
                  label: String(fd.get(`f_${f.key}_label`) ?? f.label),
                  placeholder: String(fd.get(`f_${f.key}_ph`) ?? ""),
                  required: fd.get(`f_${f.key}_req`) === "on",
                })),
              });
              if (res.ok) {
                toast.success("Saved — publish to apply");
                setOpen(false);
              } else setError(res.error);
            });
          }}
        >
          <DialogHeader>
            <DialogTitle>{panel.label}</DialogTitle>
            <DialogDescription className="font-mono text-xs">{panel.key}</DialogDescription>
          </DialogHeader>
          <div className="space-y-2">
            <Label htmlFor="p-label">Name on the screen</Label>
            <Input id="p-label" name="label" defaultValue={panel.label} maxLength={40} required />
          </div>
          <div className="space-y-2">
            <Label htmlFor="p-desc">Short description</Label>
            <Input id="p-desc" name="description" defaultValue={panel.description ?? ""} maxLength={120} />
          </div>
          <div className="space-y-2">
            <Label htmlFor="p-help">Help text</Label>
            <Textarea id="p-help" name="help" defaultValue={panel.help_text ?? ""} maxLength={300} rows={2} />
          </div>
          <fieldset className="space-y-2">
            <legend className="text-sm font-medium">Platforms</legend>
            <div className="flex flex-wrap gap-2">
              {(["android", "ios", "tv"] as const).map((k) => (
                <label key={k} className="bg-secondary/70 has-checked:bg-primary/15 has-checked:text-primary flex cursor-pointer items-center gap-2 rounded-full px-4 py-2 text-sm">
                  <input type="checkbox" name={`p_${k}`} defaultChecked={all || panel.platforms?.includes(k)} className="accent-[var(--primary)]" />
                  {k === "ios" ? "iPhone" : k === "tv" ? "Android TV" : "Android phone"}
                </label>
              ))}
            </div>
          </fieldset>
          <fieldset className="space-y-3">
            <legend className="text-sm font-medium">Form fields</legend>
            <p className="text-muted-foreground text-xs">Field names the app reads (like “host” or “mac”) can&apos;t change; you can change what users see.</p>
            {panel.fields.map((f) => (
              <div key={f.key} className="bg-secondary/40 grid gap-2 rounded-2xl p-3 sm:grid-cols-[1fr_1fr_auto]">
                <Input name={`f_${f.key}_label`} defaultValue={f.label} maxLength={40} aria-label={`${f.key} label`} />
                <Input name={`f_${f.key}_ph`} defaultValue={f.placeholder ?? ""} maxLength={80} placeholder="Placeholder" aria-label={`${f.key} placeholder`} />
                <label className="flex items-center gap-2 text-xs">
                  <input type="checkbox" name={`f_${f.key}_req`} defaultChecked={!!f.required} className="accent-[var(--primary)]" />
                  Required
                </label>
                <span className="text-muted-foreground font-mono text-[10px] sm:col-span-3">
                  {f.key} · {f.type}
                </span>
              </div>
            ))}
          </fieldset>
          {error ? (
            <p role="alert" className="text-destructive text-sm">
              {error}
            </p>
          ) : null}
          <DialogFooter>
            <Button type="submit" className="rounded-full" disabled={pending}>
              {pending ? "Saving…" : "Save"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
