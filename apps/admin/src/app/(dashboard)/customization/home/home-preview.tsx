import type { SectionRow } from "./section-dialog";

/**
 * Approximate phone preview of the app's existing home (D17: the app design stays):
 * hero banner, match cards, wide continue tiles, ranked Top 10 with big numbers,
 * channel circles and poster rails. Colours: default black & red.
 */
const C = { bg: "#0D0607", surface: "#1A0B0D", raised: "#2A1013", primary: "#E11D2E", text: "#FFFFFF", muted: "#BFAFB1" };

export function HomePreview({ sections }: { sections: SectionRow[] }) {
  return (
    <div className="w-[270px] rounded-[40px] border-[6px] border-black bg-black shadow-2xl">
      <div className="h-[560px] overflow-y-auto rounded-[34px] pb-6" style={{ background: C.bg, color: C.text }}>
        <div className="flex gap-1.5 px-3 pt-4 pb-2 text-[9px]">
          {["Home", "Live", "Movies", "Series"].map((x, i) => (
            <span key={x} className="rounded-full px-2.5 py-1" style={i === 0 ? { background: C.primary } : { background: C.surface, color: C.muted }}>
              {x}
            </span>
          ))}
        </div>
        {sections.length === 0 ? <p className="p-6 text-center text-xs" style={{ color: C.muted }}>No visible sections</p> : null}
        {sections.map((s) => (
          <Block key={s.id} s={s} />
        ))}
      </div>
    </div>
  );
}

function Title({ children }: { children: React.ReactNode }) {
  return <p className="px-3 pt-3 pb-1.5 text-[10px] font-semibold">{children}</p>;
}

function Block({ s }: { s: SectionRow }) {
  switch (s.layout) {
    case "hero":
      return (
        <div className="mx-3 mt-1 h-32 rounded-2xl p-3" style={{ background: `linear-gradient(160deg, ${C.raised}, #4a0d14 60%, ${C.primary})` }}>
          <div className="flex gap-1">
            <span className="rounded px-1 text-[7px] font-bold" style={{ background: "#F5B301", color: "#000" }}>VIP</span>
            <span className="rounded bg-white/20 px-1 text-[7px] font-bold">4K ULTRA</span>
          </div>
          <p className="mt-14 text-xs font-bold">{s.title}</p>
          <span className="mt-1 inline-block rounded-full px-2 py-0.5 text-[8px] font-semibold" style={{ background: C.primary }}>▶ Play</span>
        </div>
      );
    case "cards":
      return (
        <>
          <Title>{s.title}</Title>
          <div className="flex gap-2 overflow-hidden px-3">
            {[0, 1].map((i) => (
              <div key={i} className="flex h-14 w-32 shrink-0 items-center justify-between rounded-xl px-2 text-[8px]" style={{ background: C.surface }}>
                <span>⚽ Home</span>
                <span className="font-bold" style={{ color: C.primary }}>{i === 0 ? "LIVE" : "20:00"}</span>
                <span>Away</span>
              </div>
            ))}
          </div>
        </>
      );
    case "wide_rail":
      return (
        <>
          <Title>{s.title}</Title>
          <div className="flex gap-2 overflow-hidden px-3">
            {[0, 1, 2].map((i) => (
              <div key={i} className="relative h-16 w-28 shrink-0 overflow-hidden rounded-xl" style={{ background: C.surface }}>
                <div className="absolute inset-x-0 bottom-0 h-1" style={{ background: C.raised }}>
                  <div className="h-1" style={{ width: `${30 + i * 20}%`, background: C.primary }} />
                </div>
              </div>
            ))}
          </div>
        </>
      );
    case "ranked":
      return (
        <>
          <Title>{s.title}</Title>
          <div className="flex gap-1 overflow-hidden px-3">
            {[1, 2, 3].map((n) => (
              <div key={n} className="flex shrink-0 items-end">
                <span className="text-4xl leading-none font-black" style={{ color: "transparent", WebkitTextStroke: `1.5px ${C.primary}` }}>{n}</span>
                <div className="-ml-2 h-24 w-16 rounded-lg" style={{ background: C.surface }} />
              </div>
            ))}
          </div>
        </>
      );
    case "circles":
      return (
        <>
          <Title>{s.title}</Title>
          <div className="flex gap-2.5 overflow-hidden px-3">
            {[0, 1, 2, 3, 4].map((i) => (
              <div key={i} className="size-11 shrink-0 rounded-full border" style={{ background: C.surface, borderColor: i === 0 ? C.primary : C.raised }} />
            ))}
          </div>
        </>
      );
    case "grid":
      return (
        <>
          <Title>{s.title}</Title>
          <div className="grid grid-cols-3 gap-1.5 px-3">
            {Array.from({ length: 6 }, (_, i) => (
              <div key={i} className="aspect-[2/3] rounded-lg" style={{ background: C.surface }} />
            ))}
          </div>
        </>
      );
    default:
      return (
        <>
          <Title>{s.title}</Title>
          <div className="flex gap-1.5 overflow-hidden px-3">
            {[0, 1, 2, 3].map((i) => (
              <div key={i} className="h-24 w-16 shrink-0 rounded-lg" style={{ background: C.surface }} />
            ))}
          </div>
        </>
      );
  }
}
