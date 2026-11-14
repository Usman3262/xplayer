"use client";

import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";

export type Platform = "android" | "ios" | "tv";
export type Targeting = {
  platforms: Platform[]; // [] = all
  countries: string[]; // [] = all
  requires_login: boolean;
  starts_at: string; // datetime-local value or ""
  ends_at: string;
};

const LABEL: Record<Platform, string> = { android: "Android phone", ios: "iPhone", tv: "Android TV" };

/** "Who sees it" block shared by sections, banners, etc. */
export function TargetingFields({ value, onChange, login = true }: { value: Targeting; onChange: (v: Targeting) => void; login?: boolean }) {
  return (
    <fieldset className="space-y-3">
      <legend className="text-sm font-medium">Who sees it</legend>
      <div className="flex flex-wrap gap-2">
        {(Object.keys(LABEL) as Platform[]).map((k) => {
          const on = value.platforms.length === 0 || value.platforms.includes(k);
          return (
            <button
              key={k}
              type="button"
              onClick={() => {
                const cur: Platform[] = value.platforms.length === 0 ? ["android", "ios", "tv"] : value.platforms;
                const next = on ? cur.filter((x) => x !== k) : [...cur, k];
                onChange({ ...value, platforms: next.length === 3 ? [] : next });
              }}
              className={on ? "bg-primary/15 text-primary rounded-full px-4 py-2 text-sm" : "bg-secondary/70 text-muted-foreground rounded-full px-4 py-2 text-sm"}
            >
              {LABEL[k]}
            </button>
          );
        })}
      </div>
      <div className="grid gap-4 sm:grid-cols-2">
        <div className="space-y-2">
          <Label>Countries (optional)</Label>
          <Input
            placeholder="All — or e.g. PK, AE, GB"
            value={value.countries.join(", ")}
            onChange={(e) => onChange({ ...value, countries: e.target.value.toUpperCase().split(/[\s,]+/).filter(Boolean) })}
          />
        </div>
        {login ? (
          <label className="bg-secondary/40 flex items-center justify-between gap-3 rounded-2xl px-4">
            <span className="text-sm">Only signed-in users</span>
            <Switch checked={value.requires_login} onCheckedChange={(v) => onChange({ ...value, requires_login: v })} />
          </label>
        ) : (
          <span />
        )}
        <div className="space-y-2">
          <Label>Show from</Label>
          <Input type="datetime-local" value={value.starts_at} onChange={(e) => onChange({ ...value, starts_at: e.target.value })} />
        </div>
        <div className="space-y-2">
          <Label>Show until</Label>
          <Input type="datetime-local" value={value.ends_at} onChange={(e) => onChange({ ...value, ends_at: e.target.value })} />
        </div>
      </div>
    </fieldset>
  );
}
