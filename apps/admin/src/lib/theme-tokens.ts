/**
 * App theme tokens — the SAME keys as Flutter `AppThemeConfig` (packages/design_system).
 * Never add a key here without adding it to AppThemeConfig (and vice versa).
 */
export const THEME_TOKENS = [
  { key: "background", label: "Background", group: "Backgrounds", hint: "Screen background" },
  { key: "surface", label: "Surface", group: "Backgrounds", hint: "Cards, sheets" },
  { key: "surfaceElevated", label: "Raised surface", group: "Backgrounds", hint: "Dialogs, raised cards" },
  { key: "border", label: "Border", group: "Backgrounds", hint: "Lines and outlines" },
  { key: "primary", label: "Primary", group: "Brand", hint: "Buttons, focus, highlights" },
  { key: "primaryDim", label: "Primary (dark)", group: "Brand", hint: "Pressed / gradient start" },
  { key: "secondary", label: "Secondary", group: "Brand", hint: "Second accent, gradients" },
  { key: "gold", label: "Gold", group: "Brand", hint: "Premium / Pro" },
  { key: "textPrimary", label: "Text", group: "Text", hint: "Main text" },
  { key: "textSecondary", label: "Muted text", group: "Text", hint: "Hints, captions" },
  { key: "live", label: "Live", group: "Status", hint: "LIVE badges" },
  { key: "success", label: "Success", group: "Status", hint: "Positive / sports" },
  { key: "danger", label: "Danger", group: "Status", hint: "Errors, delete" },
] as const;

export type ThemeKey = (typeof THEME_TOKENS)[number]["key"];
export type ThemeTokens = Record<ThemeKey, string>;

export const DEFAULT_THEME: ThemeTokens = {
  background: "#0D0607",
  surface: "#1A0B0D",
  surfaceElevated: "#2A1013",
  border: "#3A1A1E",
  primary: "#E11D2E",
  primaryDim: "#A3111D",
  secondary: "#7A0C14",
  gold: "#F5B301",
  textPrimary: "#FFFFFF",
  textSecondary: "#BFAFB1",
  live: "#FF3B30",
  success: "#22C55E",
  danger: "#FF6B6B",
};

/** Quick starting points; admins can fine-tune any token afterwards. */
export const THEME_PRESETS: { name: string; tokens: ThemeTokens }[] = [
  { name: "Black & red", tokens: DEFAULT_THEME },
  {
    name: "Midnight blue",
    tokens: { ...DEFAULT_THEME, background: "#060912", surface: "#0E1424", surfaceElevated: "#16203A", border: "#22304F", primary: "#3B82F6", primaryDim: "#1D4ED8", secondary: "#1E3A8A", textSecondary: "#A9B4C8" },
  },
  {
    name: "Emerald",
    tokens: { ...DEFAULT_THEME, background: "#05100C", surface: "#0B1C16", surfaceElevated: "#12291F", border: "#1D3B2E", primary: "#10B981", primaryDim: "#047857", secondary: "#065F46", textSecondary: "#A7C4B8" },
  },
  {
    name: "Royal purple",
    tokens: { ...DEFAULT_THEME, background: "#0B0612", surface: "#170D24", surfaceElevated: "#221335", border: "#33204D", primary: "#A855F7", primaryDim: "#7E22CE", secondary: "#581C87", textSecondary: "#BCAFCB" },
  },
  {
    name: "Gold on black",
    tokens: { ...DEFAULT_THEME, background: "#0A0A0A", surface: "#151515", surfaceElevated: "#1F1F1F", border: "#2E2E2E", primary: "#F5B301", primaryDim: "#B98500", secondary: "#5C4400", textSecondary: "#B5B0A5" },
  },
];

export const HEX = /^#([0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$/;

/** Fill missing/invalid keys from the default so the editor always has a full theme. */
export function normalizeTheme(raw: Record<string, unknown> | null | undefined): ThemeTokens {
  const out = { ...DEFAULT_THEME };
  for (const t of THEME_TOKENS) {
    const v = raw?.[t.key];
    if (typeof v === "string" && HEX.test(v)) out[t.key] = v.toUpperCase();
  }
  return out;
}

function luminance(hex: string): number {
  const h = hex.replace("#", "").slice(-6);
  const [r, g, b] = [0, 2, 4].map((i) => {
    const c = parseInt(h.slice(i, i + 2), 16) / 255;
    return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/** WCAG contrast ratio (1–21). ≥ 4.5 is comfortable for normal text. */
export function contrast(a: string, b: string): number {
  const [l1, l2] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (l1 + 0.05) / (l2 + 0.05);
}
