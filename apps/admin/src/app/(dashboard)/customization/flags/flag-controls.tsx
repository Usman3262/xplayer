"use client";

import { Pencil } from "lucide-react";
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

import { setFlagEnabled, updateFlag } from "./actions";

export type FlagRow = {
  key: string;
  name: string;
  description: string;
  enabled: boolean;
  platforms: string[] | null;
  min_app_version: string | null;
  max_app_version: string | null;
  starts_at: string | null;
  ends_at: string | null;
};

const PLATFORMS = [
  { key: "android", label: "Android phone" },
  { key: "ios", label: "iPhone" },
  { key: "tv", label: "Android TV" },
] as const;

/** ISO → value for <input type="datetime-local"> in the admin's local time. */
function toLocalInput(iso: string | null): string {
  if (!iso) return "";
  const d = new Date(iso);
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

export function FlagSwitch({ flag, disabled }: { flag: FlagRow; disabled: boolean }) {
  const [pending, start] = useTransition();
  const [on, setOn] = useState(flag.enabled);
  return (
    <Switch
      checked={on}
      disabled={disabled || pending}
      aria-label={`${flag.name} ${on ? "on" : "off"}`}
      onCheckedChange={(next) => {
        setOn(next);
        start(async () => {
          const res = await setFlagEnabled(flag.key, next);
          if (res.ok) toast.success(`${flag.name} ${next ? "on" : "off"} — publish to send it to the apps`);
          else {
            setOn(!next);
            toast.error(res.error);
          }
        });
      }}
    />
  );
}

export function FlagEditDialog({ flag }: { flag: FlagRow }) {
  const [open, setOpen] = useState(false);
  const [pending, start] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const all = !flag.platforms || flag.platforms.length === 0;

  return (
    <Dialog open={open} onOpenChange={(o) => { setOpen(o); setError(null); }}>
      <DialogTrigger render={<Button size="icon" variant="ghost" className="rounded-full" aria-label={`Edit ${flag.name}`} />}>
        <Pencil />
      </DialogTrigger>
      <DialogContent className="rounded-3xl sm:max-w-lg">
        <form
          className="space-y-5"
          onSubmit={(e) => {
            e.preventDefault();
            const fd = new FormData(e.currentTarget);
            setError(null);
            start(async () => {
              const res = await updateFlag({
                key: flag.key,
                name: String(fd.get("name") ?? ""),
                description: String(fd.get("description") ?? ""),
                platforms: PLATFORMS.map((p) => p.key).filter((k) => fd.get(`p_${k}`) === "on"),
                min_app_version: String(fd.get("min") ?? ""),
                max_app_version: String(fd.get("max") ?? ""),
                starts_at: String(fd.get("from") ?? ""),
                ends_at: String(fd.get("to") ?? ""),
              });
              if (res.ok) {
                toast.success("Saved — publish to send it to the apps");
                setOpen(false);
              } else setError(res.error);
            });
          }}
        >
          <DialogHeader>
            <DialogTitle>{flag.name}</DialogTitle>
            <DialogDescription className="font-mono text-xs">{flag.key}</DialogDescription>
          </DialogHeader>

          <div className="space-y-2">
            <Label htmlFor="f-name">Name</Label>
            <Input id="f-name" name="name" defaultValue={flag.name} maxLength={60} required />
          </div>
          <div className="space-y-2">
            <Label htmlFor="f-desc">Description</Label>
            <Textarea id="f-desc" name="description" defaultValue={flag.description} maxLength={200} rows={2} required />
          </div>

          <fieldset className="space-y-2">
            <legend className="text-sm font-medium">Platforms</legend>
            <div className="flex flex-wrap gap-2">
              {PLATFORMS.map((p) => (
                <label key={p.key} className="bg-secondary/70 has-checked:bg-primary/15 has-checked:text-primary flex cursor-pointer items-center gap-2 rounded-full px-4 py-2 text-sm">
                  <input
                    type="checkbox"
                    name={`p_${p.key}`}
                    defaultChecked={all || flag.platforms?.includes(p.key)}
                    className="accent-[var(--primary)]"
                  />
                  {p.label}
                </label>
              ))}
            </div>
          </fieldset>

          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-2">
              <Label htmlFor="f-min">From app version</Label>
              <Input id="f-min" name="min" defaultValue={flag.min_app_version ?? ""} placeholder="any" />
            </div>
            <div className="space-y-2">
              <Label htmlFor="f-max">Up to app version</Label>
              <Input id="f-max" name="max" defaultValue={flag.max_app_version ?? ""} placeholder="any" />
            </div>
            <div className="space-y-2">
              <Label htmlFor="f-from">Turns on at</Label>
              <Input id="f-from" name="from" type="datetime-local" defaultValue={toLocalInput(flag.starts_at)} />
            </div>
            <div className="space-y-2">
              <Label htmlFor="f-to">Turns off at</Label>
              <Input id="f-to" name="to" type="datetime-local" defaultValue={toLocalInput(flag.ends_at)} />
            </div>
          </div>
          <p className="text-muted-foreground text-xs">Leave empty for “always”. Times are in your local time zone.</p>

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
