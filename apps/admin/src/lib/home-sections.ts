/**
 * Home section types, sources and layouts — mirrors the DB checks in migrations
 * 003/007 and the Dart `HomeSectionType` / `SectionSource` / `SectionLayout` enums
 * (packages/data/lib/src/backend/home_layout.dart). Keep all three in sync.
 */
export const SOURCES = {
  auto: { label: "Automatic", hint: "The app fills it (e.g. continue watching, favorites, live now)" },
  provider_added: { label: "Newest in the user's panel", hint: "By the panel's “added” date" },
  provider_rating: { label: "Best-rated in the user's panel", hint: "Panel rating, optionally recent only" },
  provider_category: { label: "A panel category", hint: "Matches a category/group name in the user's panel" },
  manual: { label: "Your picks", hint: "Titles you choose; hidden if the user's panel doesn't have them" },
  random: { label: "Random from the panel", hint: "Fresh mix on each visit" },
  watch_stats: { label: "Most watched on XPlayer", hint: "Needs analytics (later phase)" },
} as const;
export type SourceKey = keyof typeof SOURCES;

export const LAYOUTS = {
  rail: "Poster rail",
  wide_rail: "Wide tiles",
  grid: "Grid",
  hero: "Hero banner",
  ranked: "Ranked (big numbers)",
  circles: "Circles (channels)",
  cards: "Cards (matches)",
} as const;
export type LayoutKey = keyof typeof LAYOUTS;

export const KINDS = { mixed: "Movies + series", movie: "Movies", series: "Series", live: "Live channels" } as const;
export type KindKey = keyof typeof KINDS;

type TypeDef = {
  label: string;
  hint: string;
  sources: SourceKey[];
  layouts: LayoutKey[];
  kinds: KindKey[];
};

export const SECTION_TYPES: Record<string, TypeDef> = {
  hero_banners: { label: "Hero banner", hint: "Big rotating banner at the top (uses Banners)", sources: ["manual", "provider_added", "provider_rating"], layouts: ["hero"], kinds: ["mixed", "movie", "series"] },
  continue_watching: { label: "Continue watching", hint: "What the user started", sources: ["auto"], layouts: ["wide_rail", "rail"], kinds: ["mixed"] },
  top10: { label: "Top 10", hint: "Ranked list (uses a Top 10 list)", sources: ["provider_rating", "provider_added", "manual", "watch_stats"], layouts: ["ranked"], kinds: ["mixed", "movie", "series"] },
  new_releases: { label: "New releases", hint: "Recently released / added titles", sources: ["provider_added", "manual"], layouts: ["rail", "wide_rail", "grid"], kinds: ["movie", "series", "mixed"] },
  recently_added: { label: "Recently added", hint: "Newest in the panel", sources: ["provider_added"], layouts: ["rail", "wide_rail", "grid"], kinds: ["mixed", "movie", "series"] },
  trending: { label: "Trending", hint: "What's hot right now", sources: ["provider_rating", "watch_stats", "manual"], layouts: ["rail", "wide_rail"], kinds: ["mixed", "movie", "series"] },
  popular: { label: "Popular", hint: "Best-rated / most watched", sources: ["provider_rating", "watch_stats", "manual"], layouts: ["rail", "grid"], kinds: ["mixed", "movie", "series"] },
  live_now: { label: "Live now", hint: "Live channels", sources: ["auto", "provider_category", "manual"], layouts: ["circles", "rail"], kinds: ["live"] },
  favorites: { label: "My favorites", hint: "The user's favorites", sources: ["auto"], layouts: ["rail", "circles"], kinds: ["mixed", "live"] },
  recently_watched: { label: "Recently watched", hint: "The user's history", sources: ["auto"], layouts: ["rail", "wide_rail"], kinds: ["mixed", "live"] },
  recommended: { label: "Picked for you", hint: "Random or most watched", sources: ["random", "watch_stats", "manual"], layouts: ["rail", "wide_rail"], kinds: ["mixed", "movie", "series"] },
  category: { label: "Category", hint: "One panel category, e.g. “Netflix” or “Kids”", sources: ["provider_category"], layouts: ["rail", "wide_rail", "grid", "circles"], kinds: ["mixed", "movie", "series", "live"] },
  genre: { label: "Genre", hint: "Titles of one genre", sources: ["provider_category"], layouts: ["rail", "grid"], kinds: ["mixed", "movie", "series"] },
  collection: { label: "Collection", hint: "Your own curated list", sources: ["manual"], layouts: ["rail", "wide_rail", "grid"], kinds: ["mixed", "movie", "series", "live"] },
  matches_live: { label: "Live matches", hint: "Sports matches in progress", sources: ["auto"], layouts: ["cards"], kinds: ["live"] },
  matches_upcoming: { label: "Matches today/tomorrow", hint: "Upcoming sports matches", sources: ["auto"], layouts: ["cards"], kinds: ["live"] },
  custom: { label: "Custom", hint: "Anything you pick by hand", sources: ["manual"], layouts: ["rail", "wide_rail", "grid", "circles", "cards"], kinds: ["mixed", "movie", "series", "live"] },
};
export type SectionTypeKey = keyof typeof SECTION_TYPES;

/** Which extra parameters a source uses (stored in home_sections.params). */
export const SOURCE_PARAMS: Partial<Record<SourceKey, ("days" | "match" | "min_rating")[]>> = {
  provider_added: ["days"],
  provider_rating: ["days", "min_rating"],
  provider_category: ["match"],
};

export const ITEM_KINDS = { movie: "Movie", series: "Series", live: "Channel", link: "Link" } as const;
