"use client";

import { useState, useTransition } from "react";
import { toast } from "sonner";

import { saveSettings } from "@/app/(dashboard)/customization/actions";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Switch } from "@/components/ui/switch";

export type SettingRow = {
  key: string;
  value_type: string;
  value: unknown;
  validation: { options?: string[]; min?: number; max?: number } | null;
  description: string;
};

type Value = string | number | boolean | string[];

/**
 * Generic editor for typed app settings: picks the control from value_type
 * (bool → switch, int/number → number with min/max, enum → select, else text).
 * Labels come from `labels` or the setting's description.
 */
export function SettingsCard({
  title,
  description,
  rows,
  labels = {},
  units = {},
  canWrite,
}: {
  title: string;
  description?: string;
  rows: SettingRow[];
  labels?: Record<string, string>;
  units?: Record<string, string>;
  canWrite: boolean;
}) {
  const initial = Object.fromEntries(rows.map((r) => [r.key, r.value as Value]));
  const [vals, setVals] = useState<Record<string, Value>>(initial);
  const [pending, start] = useTransition();
  const changed = rows.filter((r) => JSON.stringify(vals[r.key]) !== JSON.stringify(initial[r.key]));

  return (
    <section className="bg-card/60 space-y-5 rounded-[28px] border p-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h2 className="font-semibold">{title}</h2>
          {description ? <p className="text-muted-foreground text-sm">{description}</p> : null}
        </div>
        <Button
          className="rounded-full"
          disabled={!canWrite || changed.length === 0 || pending}
          onClick={() =>
            start(async () => {
              const res = await saveSettings(changed.map((r) => ({ key: r.key, value: vals[r.key] })));
              if (res.ok) toast.success("Saved — publish to send it to the apps");
              else toast.error(res.error);
            })
          }
        >
          {pending ? "Saving…" : changed.length ? `Save ${changed.length}` : "Save"}
        </Button>
      </div>
      <div className="grid gap-3 md:grid-cols-2">
        {rows.map((r) => {
          const v = vals[r.key];
          const label = labels[r.key] ?? r.description;
          const id = `s-${r.key}`;
          return (
            <div key={r.key} className="bg-secondary/40 flex items-center justify-between gap-4 rounded-2xl p-4">
              <label htmlFor={id} className="min-w-0">
                <span className="block text-sm font-medium">{label}</span>
                <span className="text-muted-foreground block truncate text-xs">
                  {labels[r.key] ? r.description : r.key}
                </span>
              </label>
              {r.value_type === "bool" ? (
                <Switch id={id} checked={v === true} disabled={!canWrite} onCheckedChange={(x) => setVals({ ...vals, [r.key]: x })} />
              ) : r.value_type === "enum" ? (
                <select
                  id={id}
                  value={String(v)}
                  disabled={!canWrite}
                  onChange={(e) => setVals({ ...vals, [r.key]: e.target.value })}
                  className="bg-secondary focus:ring-primary/40 h-10 rounded-full px-4 text-sm outline-none focus:ring-2"
                >
                  {(r.validation?.options ?? []).map((o) => (
                    <option key={o} value={o}>
                      {o}
                    </option>
                  ))}
                </select>
              ) : r.value_type === "int" || r.value_type === "number" ? (
                <span className="flex items-center gap-2">
                  <Input
                    id={id}
                    type="number"
                    value={Number(v)}
                    min={r.validation?.min}
                    max={r.validation?.max}
                    step={r.value_type === "int" ? 1 : "any"}
                    disabled={!canWrite}
                    onChange={(e) => setVals({ ...vals, [r.key]: Number(e.target.value) })}
                    className="h-10 w-28 text-right tabular-nums"
                  />
                  {units[r.key] ? <span className="text-muted-foreground w-8 text-xs">{units[r.key]}</span> : null}
                </span>
              ) : r.value_type === "string_list" ? (
                // Comma-separated in the box, saved as a list.
                <Input
                  id={id}
                  value={Array.isArray(v) ? v.join(", ") : String(v ?? "")}
                  disabled={!canWrite}
                  onChange={(e) =>
                    setVals({
                      ...vals,
                      [r.key]: e.target.value.split(",").map((x) => x.trim()).filter((x) => x.length > 0),
                    })
                  }
                  className="h-10 w-72"
                />
              ) : (
                <Input
                  id={id}
                  value={String(v ?? "")}
                  disabled={!canWrite}
                  onChange={(e) => setVals({ ...vals, [r.key]: e.target.value })}
                  className="h-10 w-56"
                />
              )}
            </div>
          );
        })}
      </div>
    </section>
  );
}
