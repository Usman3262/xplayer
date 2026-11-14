"use client";

import { AlertTriangle, RotateCcw } from "lucide-react";
import { useState, useTransition } from "react";
import { toast } from "sonner";

import { ImageUpload } from "@/components/customization/image-upload";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { cn } from "@/lib/utils";
import { contrast, DEFAULT_THEME, HEX, THEME_PRESETS, THEME_TOKENS, type ThemeKey, type ThemeTokens } from "@/lib/theme-tokens";

import { saveBranding, saveTheme, type BrandingInput } from "./actions";
import { PhonePreview, TvPreview } from "./app-preview";

type Branding = { display_name: string; tagline: string; logo_url: string; splash_url: string };

export function ThemeEditor({
  initial,
  branding,
  appName,
  canWrite,
}: {
  initial: ThemeTokens;
  branding: Branding;
  appName: string;
  canWrite: boolean;
}) {
  const [t, setT] = useState<ThemeTokens>(initial);
  const [b, setB] = useState<Branding>(branding);
  const [savingTheme, startTheme] = useTransition();
  const [savingBrand, startBrand] = useTransition();
  const themeDirty = JSON.stringify(t) !== JSON.stringify(initial);
  const brandDirty = JSON.stringify(b) !== JSON.stringify(branding);
  const shownName = b.display_name.trim() || appName;

  const set = (k: ThemeKey, v: string) => setT((prev) => ({ ...prev, [k]: v }));
  const warnings = [
    { label: "Text on background", ratio: contrast(t.textPrimary, t.background), min: 4.5 },
    { label: "Text on surface", ratio: contrast(t.textPrimary, t.surface), min: 4.5 },
    { label: "Muted text on background", ratio: contrast(t.textSecondary, t.background), min: 3 },
    { label: "White on primary (buttons)", ratio: contrast("#FFFFFF", t.primary), min: 3 },
  ].filter((w) => w.ratio < w.min);
  const groups = [...new Set(THEME_TOKENS.map((x) => x.group))];

  return (
    <div className="grid gap-8 2xl:grid-cols-[minmax(0,1fr)_auto]">
      <div className="flex min-w-0 flex-col gap-6">
        {/* Presets */}
        <section className="bg-card/60 space-y-4 rounded-[28px] border p-6">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <h2 className="font-semibold">Theme colours</h2>
            <div className="flex gap-2">
              <Button variant="ghost" className="rounded-full" disabled={!canWrite} onClick={() => setT(DEFAULT_THEME)}>
                <RotateCcw /> Default
              </Button>
              <Button
                className="rounded-full"
                disabled={!canWrite || !themeDirty || savingTheme}
                onClick={() =>
                  startTheme(async () => {
                    const res = await saveTheme(t);
                    if (res.ok) toast.success("Theme saved — publish to send it to the apps");
                    else toast.error(res.error);
                  })
                }
              >
                {savingTheme ? "Saving…" : "Save theme"}
              </Button>
            </div>
          </div>
          <div className="flex flex-wrap gap-2">
            {THEME_PRESETS.map((p) => (
              <button
                key={p.name}
                type="button"
                disabled={!canWrite}
                onClick={() => setT(p.tokens)}
                className="bg-secondary/70 hover:bg-secondary flex items-center gap-2 rounded-full py-1.5 pr-4 pl-1.5 text-sm disabled:opacity-50"
              >
                <span className="flex size-7 overflow-hidden rounded-full border">
                  <span className="flex-1" style={{ background: p.tokens.background }} />
                  <span className="flex-1" style={{ background: p.tokens.primary }} />
                </span>
                {p.name}
              </button>
            ))}
          </div>

          {warnings.length ? (
            <div className="flex gap-3 rounded-2xl bg-amber-500/10 p-3 text-sm text-amber-300">
              <AlertTriangle className="size-5 shrink-0" />
              <div>
                Hard to read:{" "}
                {warnings.map((w) => `${w.label} (${w.ratio.toFixed(1)}:1, aim for ${w.min}:1)`).join(" · ")}
              </div>
            </div>
          ) : null}

          {groups.map((g) => (
            <div key={g} className="space-y-3">
              <p className="text-muted-foreground text-xs font-medium tracking-wide uppercase">{g}</p>
              <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
                {THEME_TOKENS.filter((x) => x.group === g).map((tok) => {
                  const v = t[tok.key];
                  const valid = HEX.test(v);
                  return (
                    <label key={tok.key} className="bg-secondary/40 flex items-center gap-3 rounded-2xl p-2.5">
                      <input
                        type="color"
                        value={valid ? v.slice(0, 7) : "#000000"}
                        disabled={!canWrite}
                        onChange={(e) => set(tok.key, e.target.value.toUpperCase())}
                        className="size-10 shrink-0 cursor-pointer rounded-xl border-0 bg-transparent p-0"
                        aria-label={tok.label}
                      />
                      <span className="min-w-0 flex-1">
                        <span className="block text-sm font-medium">{tok.label}</span>
                        <span className="text-muted-foreground block truncate text-xs">{tok.hint}</span>
                      </span>
                      <Input
                        value={v}
                        disabled={!canWrite}
                        onChange={(e) => set(tok.key, e.target.value.trim())}
                        className={cn("h-9 w-24 font-mono text-xs uppercase", !valid && "border-destructive")}
                        aria-label={`${tok.label} hex`}
                      />
                    </label>
                  );
                })}
              </div>
            </div>
          ))}
        </section>

        {/* Branding */}
        <section className="bg-card/60 space-y-5 rounded-[28px] border p-6">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div>
              <h2 className="font-semibold">Branding</h2>
              <p className="text-muted-foreground text-sm">Leave empty to use what is built into the apps.</p>
            </div>
            <Button
              className="rounded-full"
              disabled={!canWrite || !brandDirty || savingBrand}
              onClick={() =>
                startBrand(async () => {
                  const res = await saveBranding(b satisfies BrandingInput);
                  if (res.ok) toast.success("Branding saved — publish to send it to the apps");
                  else toast.error(res.error);
                })
              }
            >
              {savingBrand ? "Saving…" : "Save branding"}
            </Button>
          </div>
          <div className="grid gap-4 md:grid-cols-2">
            <div className="space-y-2">
              <Label htmlFor="b-name">Name shown in the apps</Label>
              <Input
                id="b-name"
                value={b.display_name}
                maxLength={40}
                placeholder={appName}
                disabled={!canWrite}
                onChange={(e) => setB({ ...b, display_name: e.target.value })}
              />
              <p className="text-muted-foreground text-xs">The phone/TV launcher name comes from the app build.</p>
            </div>
            <div className="space-y-2">
              <Label htmlFor="b-tag">Tagline</Label>
              <Input
                id="b-tag"
                value={b.tagline}
                maxLength={80}
                placeholder="Optional"
                disabled={!canWrite}
                onChange={(e) => setB({ ...b, tagline: e.target.value })}
              />
            </div>
            <div className="space-y-2">
              <Label>Logo</Label>
              <ImageUpload value={b.logo_url || null} onChange={(url) => setB({ ...b, logo_url: url ?? "" })} folder="branding" aspect="aspect-square max-w-40" label="Upload logo" />
            </div>
            <div className="space-y-2">
              <Label>Splash image</Label>
              <ImageUpload value={b.splash_url || null} onChange={(url) => setB({ ...b, splash_url: url ?? "" })} folder="branding" aspect="aspect-[9/16] max-w-40" label="Upload splash" />
            </div>
          </div>
        </section>
      </div>

      {/* Live preview */}
      <aside className="flex flex-col items-center gap-6 2xl:sticky 2xl:top-6 2xl:self-start">
        <p className="text-muted-foreground text-xs tracking-wide uppercase">Live preview</p>
        <PhonePreview t={t} name={shownName} logo={b.logo_url || null} />
        <TvPreview t={t} name={shownName} />
      </aside>
    </div>
  );
}
