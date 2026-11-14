"use client";

import { Plus, Trash2 } from "lucide-react";
import { useState, useTransition } from "react";
import { toast } from "sonner";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { fmtDateTime } from "@/lib/dates";

import { addOverride, deleteOverride } from "./actions";

export type OverrideRow = {
  id: string;
  flag_key: string;
  target_type: "country" | "user" | "plan";
  target_label: string;
  enabled: boolean;
  starts_at: string | null;
  ends_at: string | null;
};

const selectCls = "bg-secondary/70 focus:ring-primary/40 h-10 w-full rounded-full px-4 text-sm outline-none focus:ring-2";

/**
 * Exceptions to a flag for one country or one user. Users get them only when
 * signed in (guests are anonymous). User exceptions win over country ones.
 */
export function OverridesPanel({ rows, flags, canWrite }: { rows: OverrideRow[]; flags: { key: string; name: string }[]; canWrite: boolean }) {
  const [pending, start] = useTransition();
  const name = (k: string) => flags.find((f) => f.key === k)?.name ?? k;
  return (
    <section className="bg-card/60 space-y-4 rounded-[28px] border p-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h2 className="font-semibold">Exceptions</h2>
          <p className="text-muted-foreground text-sm">Turn a feature on or off for one country or one signed-in user. A user exception beats a country one.</p>
        </div>
        {canWrite ? <AddOverrideDialog flags={flags} /> : null}
      </div>
      {rows.length === 0 ? (
        <p className="text-muted-foreground rounded-2xl border border-dashed p-5 text-center text-sm">No exceptions.</p>
      ) : (
        <ul className="divide-y">
          {rows.map((o) => (
            <li key={o.id} className="flex flex-wrap items-center gap-3 py-3 text-sm">
              <span className="font-medium">{name(o.flag_key)}</span>
              <Badge className={o.enabled ? "rounded-full bg-emerald-500/15 text-emerald-400" : "bg-destructive/15 text-destructive rounded-full"}>{o.enabled ? "on" : "off"}</Badge>
              <span className="text-muted-foreground">
                for {o.target_type} <span className="text-foreground">{o.target_label}</span>
              </span>
              {o.starts_at || o.ends_at ? (
                <span className="text-muted-foreground text-xs">
                  {o.starts_at ? `from ${fmtDateTime(o.starts_at)} ` : ""}
                  {o.ends_at ? `until ${fmtDateTime(o.ends_at)}` : ""}
                </span>
              ) : null}
              {canWrite ? (
                <Button
                  size="icon"
                  variant="ghost"
                  className="text-destructive hover:text-destructive ml-auto rounded-full"
                  aria-label="Remove exception"
                  disabled={pending}
                  onClick={() =>
                    start(async () => {
                      const res = await deleteOverride(o.id);
                      if (res.ok) toast.success("Exception removed — publish to apply");
                      else toast.error(res.error);
                    })
                  }
                >
                  <Trash2 />
                </Button>
              ) : null}
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

function AddOverrideDialog({ flags }: { flags: { key: string; name: string }[] }) {
  const [open, setOpen] = useState(false);
  const [type, setType] = useState<"country" | "user">("country");
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();
  return (
    <Dialog
      open={open}
      onOpenChange={(o) => {
        setOpen(o);
        setError(null);
      }}
    >
      <DialogTrigger render={<Button className="rounded-full" />}>
        <Plus /> Add exception
      </DialogTrigger>
      <DialogContent className="rounded-3xl sm:max-w-md">
        <form
          className="space-y-4"
          onSubmit={(e) => {
            e.preventDefault();
            const fd = new FormData(e.currentTarget);
            setError(null);
            start(async () => {
              const res = await addOverride({
                flag_key: String(fd.get("flag") ?? ""),
                target_type: type,
                target: String(fd.get("target") ?? ""),
                enabled: fd.get("enabled") === "on",
                starts_at: String(fd.get("from") ?? ""),
                ends_at: String(fd.get("to") ?? ""),
              });
              if (res.ok) {
                toast.success("Exception added — publish to apply");
                setOpen(false);
              } else setError(res.error);
            });
          }}
        >
          <DialogHeader>
            <DialogTitle>Add exception</DialogTitle>
            <DialogDescription>Overrides the feature for one country or one signed-in user.</DialogDescription>
          </DialogHeader>
          <div className="space-y-2">
            <Label>Feature</Label>
            <select name="flag" className={selectCls} required>
              {flags.map((f) => (
                <option key={f.key} value={f.key}>
                  {f.name}
                </option>
              ))}
            </select>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-2">
              <Label>For</Label>
              <select className={selectCls} value={type} onChange={(e) => setType(e.target.value as "country" | "user")}>
                <option value="country">A country</option>
                <option value="user">A user</option>
              </select>
            </div>
            <div className="space-y-2">
              <Label>{type === "country" ? "Country code" : "User email"}</Label>
              <Input name="target" required placeholder={type === "country" ? "PK" : "name@example.com"} maxLength={type === "country" ? 2 : 200} />
            </div>
          </div>
          <label className="bg-secondary/40 flex items-center justify-between rounded-2xl px-4 py-3 text-sm">
            Feature on for them
            <input type="checkbox" name="enabled" defaultChecked className="size-4 accent-[var(--primary)]" />
          </label>
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-2">
              <Label>From (optional)</Label>
              <Input type="datetime-local" name="from" />
            </div>
            <div className="space-y-2">
              <Label>Until (optional)</Label>
              <Input type="datetime-local" name="to" />
            </div>
          </div>
          {error ? (
            <p role="alert" className="text-destructive text-sm">
              {error}
            </p>
          ) : null}
          <DialogFooter>
            <Button type="submit" className="rounded-full" disabled={pending}>
              {pending ? "Adding…" : "Add exception"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
