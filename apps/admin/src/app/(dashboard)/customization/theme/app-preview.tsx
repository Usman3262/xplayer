import { Gem, Info, ListVideo, Play, Radio, Star, Tv2 } from "lucide-react";

import type { ThemeTokens } from "@/lib/theme-tokens";

/**
 * Approximate preview of the apps with the given tokens (phone + TV), in the
 * style of the reference design. Pure CSS — only for judging colours.
 */
export function PhonePreview({ t, name, logo }: { t: ThemeTokens; name: string; logo: string | null }) {
  const grad = `linear-gradient(135deg, ${t.primaryDim}, ${t.primary})`;
  return (
    <div className="mx-auto w-[260px] shrink-0 rounded-[40px] border-[6px] border-black p-0 shadow-2xl" style={{ background: "#000" }}>
      <div className="h-[520px] overflow-hidden rounded-[34px] px-4 pt-5 pb-4" style={{ background: t.background, color: t.textPrimary }}>
        <div className="flex items-center justify-between rounded-2xl px-3 py-2" style={{ background: t.surface }}>
          <span className="flex items-center gap-2 text-sm font-semibold">
            {logo ? (
              // eslint-disable-next-line @next/next/no-img-element -- preview of an uploaded URL
              <img src={logo} alt="" className="size-5 rounded" />
            ) : null}
            {name}
          </span>
          <span className="flex flex-col gap-0.5">
            {[0, 1, 2].map((i) => (
              <span key={i} className="block h-0.5 w-4 rounded" style={{ background: t.textPrimary }} />
            ))}
          </span>
        </div>
        <div className="mt-3 flex gap-2">
          <span className="flex items-center gap-1.5 rounded-xl px-3 py-1.5 text-xs font-semibold" style={{ background: t.surfaceElevated }}>
            <Gem className="size-3.5" style={{ color: t.gold }} /> Go pro
          </span>
          <span className="ml-auto flex items-center gap-1 rounded-xl border px-2.5 py-1.5 text-[10px]" style={{ borderColor: t.border, color: t.textSecondary }}>
            <Info className="size-3" /> How to watch
          </span>
        </div>
        <div className="mt-3 flex items-center gap-3 rounded-2xl p-3" style={{ background: grad }}>
          <Star className="size-7 shrink-0" />
          <div className="text-xs leading-tight">
            <p className="font-semibold">Sport Events</p>
            <p className="opacity-80">Watch the latest matches now</p>
          </div>
        </div>
        <div className="mt-4 grid grid-cols-2 gap-2.5">
          {[
            { icon: Play, label: "Movies" },
            { icon: ListVideo, label: "Series" },
            { icon: Radio, label: "Live TV" },
            { icon: Tv2, label: "Sports" },
          ].map(({ icon: Icon, label }) => (
            <div key={label} className="flex h-24 flex-col items-center justify-center gap-2 rounded-2xl text-xs" style={{ background: grad, opacity: 0.92 }}>
              <Icon className="size-6" />
              {label}
            </div>
          ))}
        </div>
        <div className="mt-4 flex items-center gap-2 rounded-xl px-3 py-2 text-[11px]" style={{ background: t.surface }}>
          <span className="rounded px-1.5 py-0.5 text-[9px] font-bold" style={{ background: t.live }}>LIVE</span>
          <span className="truncate" style={{ color: t.textSecondary }}>Now: Evening news</span>
          <span className="ml-auto size-2 rounded-full" style={{ background: t.success }} />
        </div>
      </div>
    </div>
  );
}

export function TvPreview({ t, name }: { t: ThemeTokens; name: string }) {
  return (
    <div className="w-full max-w-[420px] rounded-2xl border-[5px] border-black shadow-2xl">
      <div className="aspect-video overflow-hidden rounded-lg p-3" style={{ background: t.background, color: t.textPrimary }}>
        <div className="flex items-center gap-3 text-[10px]">
          <span className="font-bold">{name}</span>
          {["Home", "Live TV", "Movies", "Series"].map((x, i) => (
            <span
              key={x}
              className="rounded-full px-2 py-0.5"
              style={i === 0 ? { background: t.primary, color: "#fff" } : { color: t.textSecondary }}
            >
              {x}
            </span>
          ))}
        </div>
        <div className="mt-2 h-16 rounded-lg p-2" style={{ background: `linear-gradient(90deg, ${t.surfaceElevated}, ${t.secondary})` }}>
          <p className="text-[11px] font-semibold">Featured tonight</p>
          <span className="mt-1 inline-block rounded px-2 py-0.5 text-[8px] font-semibold" style={{ background: t.primary }}>Play</span>
        </div>
        <p className="mt-2 text-[9px]" style={{ color: t.textSecondary }}>Top 10 this week</p>
        <div className="mt-1 flex gap-1.5">
          {Array.from({ length: 6 }, (_, i) => (
            <div
              key={i}
              className="aspect-[2/3] flex-1 rounded"
              style={{ background: t.surface, outline: i === 1 ? `2px solid ${t.primary}` : `1px solid ${t.border}` }}
            />
          ))}
        </div>
      </div>
    </div>
  );
}
