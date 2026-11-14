# XPlayer — roadmap & progress (read first, update last)

How to use: work on the **first unchecked step** (`[ ]`). When a step is finished,
tick it, write *how it was tested*, and move the "▶ NEXT" marker. Status words:
implemented / tested (how) / verified on device / untested.

Spec: `new-platform.md` · Rules: `CLAUDE.md` · App "where to change": `XPLAYER_CHECKLIST.md`
· Provider protocol notes: `docs/PROVIDER_PROTOCOLS.md`

---

## ▶ NEXT
**Phase 1 · Step 1.3 — migration 002: app configuration** (`app_settings`, feature flags +
overrides, app versions, maintenance, onboarding panel types, theme, config versions,
RPC `get_app_config(platform, app_version)`), RLS + live checks, push, regenerate types.

## Waiting on you
- [ ] Add the **secret key** to `apps/admin/.env.local` → `SUPABASE_SECRET_KEY=` (Supabase →
  Project Settings → API keys → secret). Needed from step 2.1. Never paste it in chat.
- [ ] Add **`TMDB_API_KEY`** as a Supabase Edge Function secret (needed at step 1.7).
- [ ] **Sports API**: which provider? (e.g. API-Football / football-data.org / TheSportsDB)
  — needed at step 3.9; key goes in Supabase secrets.
- [ ] You can delete the empty `supabase/` folder at the repo root (left from the first link).
- [ ] **Make yourself super admin** (needed for step 2.1): Supabase → Authentication → Users →
  *Add user* (your email + password, auto-confirm), then SQL editor:
  `select public.bootstrap_super_admin('your@email');` (works only once, while no admin exists).

## Answers received (2026-11-14)
- Q1 Supabase: hosted project `phkqmojtdyaohiixakvv` (free tier). CLI linked from `apps/admin`.
- Q2 Admin in this repo at `apps/admin`, self-contained like its own repo; **all Supabase
  files (migrations, functions, seed, tests) live in `apps/admin/supabase/`**.
- Q3 TMDB key → you add it as a Supabase secret.
- Q4 Name stays **XPlayer**.
- Q5 Build FCM push but **disabled by a feature flag** in admin; in-app inbox for now.
- Q6 Sports (matches & lineups) from an **external API** (provider to choose).

## Decisions made (defaults — change any time)
| # | Decision | Why |
|---|---|---|
| D1 | Admin = **Next.js** (App Router, TS, Tailwind, shadcn/ui) in `apps/admin` | User request; React-based so spec still holds |
| D2 | Backend = **Supabase only** (no Node/Python server) | Spec §1, §29 |
| D3 | Keep current player engine **media_kit (mpv)** for now; revisit ExoPlayer/AVPlayer later | Already tuned for IPTV (ts/hls/mkv); spec's engines are a later option |
| D4 | Local cache = **Drift (SQLite)** | Spec §2.2; good for big catalogs + search |
| D5 | Provider adapters map into the **existing domain entities** so current screens keep working | "Don't change core architecture" |
| D6 | App config delivered as **one versioned JSON** from RPC `get_app_config(platform, app_version)`; cached on device; Realtime only on the version row | Fast start, few reads |
| D7 | TMDB only via Edge Function `metadata-tmdb`, cached in global catalog | Key stays secret; one fetch serves all users |
| D8 | Login **optional** by default (`auth.mode`: optional/required/disabled from admin) | User request |
| D9 | First screen after splash = **Choose your panel** (types from admin config) | User request |
| D11 | npm (no pnpm installed); no Docker → no local Supabase, migrations pushed to the hosted project | Tools on this PC |
| D12 | Next.js 16.4 with Cache Components + Partial Prefetching; session reads inside `<Suspense>` | Next 16 defaults |
| D10 | Provider credentials on device in secure storage; cloud sync of them only encrypted + opt-in | Spec §15.4 |

---

## Phase 0 — Planning ✅
- [x] 0.1 Read full spec `new-platform.md` and `neo-channel-tester.html` (Neo = Xtream
  Codes panel: `player_api.php`, live `.ts`, VOD/series by container extension).
- [x] 0.2 Research Xtream / M3U / Stalker-MAC protocols → `docs/PROVIDER_PROTOCOLS.md`.
- [x] 0.3 Research admin design + Next.js/Supabase security practices (notes in §Research).
- [x] 0.4 New `CLAUDE.md` rules (no hard-code, security, performance, admin, DB, quality gates).
- [x] 0.5 This roadmap + feature → admin map + old-backend → new-source map.
- [x] 0.6 `neo-channel-tester.html` added to `.gitignore` (contains real credentials).

## Phase 1 — Foundation (Supabase + admin skeleton)
- [x] 1.1 Scaffold `apps/admin` (Next.js 16.4, React 19.3, TS strict, Tailwind 4, shadcn/ui,
  ESLint, npm) + `apps/admin/supabase` (`supabase init`, link moved here, `migration list`
  works against the hosted project). Env: `.env.example` (tracked), `.env.local` (ignored,
  URL + publishable key). Supabase clients: browser, server (per request, RLS), admin
  (service role, `server-only`), `proxy.ts` session refresh + optimistic redirect to `/login`.
  Scripts: `typecheck`, `db:push`, `db:types`. Placeholder `/` and `/login`.
  *Tested:* lint ✓, typecheck ✓, `next build` ✓, `next start` smoke: `/` → 307 `/login?next=/`,
  `/login` → 200. No real sign-in yet (step 2.1).
- [x] 1.2 Migration 001 `20261114000001_identity_rbac.sql` — `profiles` (auto-created per auth
  user, guest flag, admin-only status), `admin_permissions` (28 keys), `admin_roles` (7 system
  roles + permission sets), `admin_role_permissions`, `admin_user_roles`, `has_permission()`,
  `is_admin()`, `my_permissions()`, append-only `audit_logs` + `log_audit()`,
  `bootstrap_super_admin()` (one-time, not callable over the API). RLS on all 6 tables;
  users can only edit their own harmless profile columns.
  *Tested:* `supabase db push` applied to the hosted project; `supabase db lint` no errors;
  live REST checks as anonymous: all 5 tables and all 5 RPCs → 42501 permission denied.
  pgTAP file `supabase/tests/001_identity_rbac_test.sql` written (12 checks) but **not run**
  (needs Docker). Signed-in checks pending a real admin user (step 2.1).
- [ ] 1.3 Migration 002 — app configuration: `app_settings` (typed key/value with
  schema + version), `feature_flags`, `feature_overrides`, `app_versions`,
  `maintenance_windows`, `onboarding_panel_types`, `theme` (JSON matching `AppThemeConfig`),
  `config_versions` (publish history). RPC `get_app_config(platform, app_version)`. RLS + tests.
- [ ] 1.4 Migration 003 — home builder & merchandising: `home_sections`
  (type: continue_watching, top10, banners, new, recently_added, trending, live_now,
  matches, lineups, category, custom…, source: auto/manual/random, targeting, schedule,
  order), `home_section_items`, `banners`, `top10_lists` + items. RLS + tests.
- [ ] 1.5 Migration 004 — global catalog: `global_movies/series/seasons/episodes/channels`,
  `genres`, `countries`, `languages`, `content_external_ids`, `content_artwork`,
  `content_overrides` (admin edits), search indexes (pg_trgm). RLS + tests.
- [ ] 1.6 Migration 005 — sports: `competitions`, `teams`, `matches`, `match_lineups`,
  `match_events`, channel links. RLS + tests.
- [ ] 1.7 Edge Function `metadata-tmdb` (lookup by title/year/tmdb id, cache to global
  catalog, rate-limit, key from secrets). Tests.
- [ ] 1.8 Generate DB types for TS (`apps/admin`) ✅ via `npm run db:types` (regenerate after every
  migration) and Dart (`packages/data`) ⏳.

## Phase 2 — Admin panel base
- [ ] 2.1 Admin auth (Supabase Auth, email/password + MFA), admin-only middleware,
  permission guard helper for server actions/routes.
- [ ] 2.2 Layout: sidebar modules, top bar, theme (dark-first), breadcrumbs, command
  palette, toasts, skeletons, empty/error states. Shared DataTable (server pagination,
  filters, search), Form kit (zod + react-hook-form), image upload to Storage.
- [ ] 2.3 Audit log viewer + every server action writes `audit_logs`.
- [ ] 2.4 Admin users & roles screen (Super Admin, Admin, Content Manager,
  Subscription Manager, Marketing Manager, Support Agent, Analyst).

## Phase 3 — Admin "App Customization" tab
- [ ] 3.1 Branding & theme: logo/splash upload, colours → `AppThemeConfig` JSON, live preview.
- [ ] 3.2 Feature flags (global / android / ios / tv / plan / country / version / user, schedule).
- [ ] 3.3 Login policy (optional/required/disabled), guest limits, registration on/off.
- [ ] 3.4 Onboarding "Choose your panel": enable/disable/order Xtream, M3U, Stalker-MAC,
  custom labels/help text, default ports, connect timeout.
- [ ] 3.5 Home builder: add/remove/reorder/rename sections, source = auto / manual pick /
  random / TMDB trending, targeting, schedule, preview (phone + TV), publish.
- [ ] 3.6 Banners (hero carousel): image, title, deep link, schedule, targeting.
- [ ] 3.7 Top 10 lists (manual / auto from analytics / TMDB trending), per country/platform.
- [ ] 3.8 "New" / "Recently added" rules (provider added date, TMDB release, manual).
- [ ] 3.9 Sports: matches, lineups, competitions, which channel shows a match.
- [ ] 3.10 Player defaults, cache policy, min/recommended app version, maintenance mode.
- [ ] 3.11 Publish flow: draft → preview → publish (bumps config version, app refreshes).

## Phase 4 — Flutter: Supabase + remote config
- [ ] 4.1 Add `supabase_flutter`; config from `--dart-define` / `app.config`-style env (no keys in code).
- [ ] 4.2 `RemoteConfigRepository`: load cached → fetch `get_app_config` if version
  changed → validate → apply (theme via `AppThemeConfig.applyJson`, flags, home layout).
- [ ] 4.3 Guest mode default; optional sign-in/up screens (Supabase Auth); policy from config.
- [ ] 4.4 Maintenance / min-version gate from config.

## Phase 5 — Provider engine ("Choose your panel")
- [ ] 5.1 `ProviderAdapter` interface + unified models + error/status model (spec §3.5).
- [ ] 5.2 Xtream adapter (auth/account info, categories, live/vod/series, series info,
  vod info, short EPG / xmltv, URL builder, output format choice). Tests with recorded JSON.
- [ ] 5.3 M3U adapter (URL/file, EXTINF attrs, groups, tvg-id, isolate parser, dedupe).
- [ ] 5.4 Stalker/MAC adapter (handshake/token, profile, genres, channels, VOD, create_link,
  token renew). Tests.
- [ ] 5.5 Connection manager: multiple panels, secure storage, test connection, status,
  expiry, primary, enable/disable, last sync.
- [ ] 5.6 Onboarding UI (phone + TV): choose panel → form → test → connect in seconds
  (account check first, catalog in background, cache-first).

## Phase 6 — Catalog, cache, sync
- [ ] 6.1 Drift local DB: categories, channels, movies, series, episodes, EPG window, sync cursors.
- [ ] 6.2 Incremental sync per connection (hashes/counts/timestamps), background, resumable.
- [ ] 6.3 Enrichment: match provider items → global catalog (tmdb id / title+year),
  missing metadata via `metadata-tmdb`; admin overrides win.
- [ ] 6.4 Data sources wired: home sections resolve from config + local catalog + global catalog.

## Phase 7 — Flutter screens on the new data
- [ ] 7.1 Home (dynamic sections), 7.2 Live TV + EPG, 7.3 Movies, 7.4 Series,
  7.5 Search (local FTS + global), 7.6 Player (direct URLs from adapter, resume),
  7.7 Favorites / history / continue watching (local; cloud when signed in),
  7.8 Sports (matches & lineups from Supabase), 7.9 Settings (panels, playback, language,
  parental, about). TV versions of each.

## Phase 8 — Accounts & devices
- [ ] Profiles, devices & sessions, cloud sync of favorites/history, guest → account migration,
  account deletion / data export.

## Phase 9 — Business
- [ ] Plans & entitlements engine, payments (store billing / manual), ads & placements,
  coupons/referrals, notification center (inbox; push after Q5).

## Phase 10 — Analytics, support, hardening, release
- [ ] Aggregated analytics, content reports, support tickets, provider health,
  security audit (RLS tests, key scan), performance on low-end TV box, store prep.

---

## Feature → admin control map (every app feature must be controllable)
| App feature (today) | Admin module | Phase |
|---|---|---|
| App name, logo, splash, theme colours | App Customization → Branding & Theme | 3.1 |
| Home rails (Top 10, New, Recently added, Trending, Continue watching, categories) | Home builder / Top 10 / New rules | 3.5, 3.7, 3.8 |
| Hero banners / promos | Banners | 3.6 |
| Live TV + EPG | Feature flags + Catalog (channels, EPG sources) | 3.2, 6 |
| Movies / Series / details / trailers | Catalog (global + overrides, TMDB) | 1.5, 6.3 |
| Sports: match centre, lineups, standings | Sports | 3.9 |
| Kids section, parental PIN | Feature flags + Catalog categories (kids) | 3.2 |
| Clips feed | Feature flag + Home builder section | 3.2, 3.5 |
| Search | Settings (search behaviour) | 3.10 |
| Downloads / offline | Feature flag + plan entitlement | 3.2, 9 |
| Profiles, avatars | Users / Plans (profile limit) | 8, 9 |
| Login, register, MFA, sessions, devices, TV pairing | Login policy, Users, Devices | 3.3, 8 |
| Notifications inbox / alerts | Notification center | 9 |
| In-app update / min version / maintenance | App versions & maintenance | 3.10 |
| Player prefs (speed, audio/subtitle defaults, decoder) | Player defaults | 3.10 |
| Appearance presets, language (EN/AR/UR) | Theme + Languages | 3.1 |
| Subscription screen | Plans & entitlements | 9 |
| Diagnostics / speed test | Feature flag | 3.2 |
| Legal (terms, privacy) | Settings → Legal pages (rich text) | 3.10 |
| Choose your panel (Xtream/M3U/Stalker) | Onboarding panel types | 3.4 |

## Old backend → new source (what the app used to get from our server)
| Old endpoint (removed server) | New source |
|---|---|
| `/catalog/live|vod|series/categories`, lists, `/catalog/vod/:id/info`, `/catalog/series/:id` | Provider adapter (Xtream/M3U/Stalker) + local cache |
| Missing metadata (posters, cast, backdrops, trailers) — app used to call TMDB | `metadata-tmdb` Edge Function → global catalog (cached) |
| `/catalog/top10` | `top10_lists` (manual / auto / TMDB trending) via app config |
| Home rails (new, recent, trending…) | `home_sections` + rules (auto / manual / random) |
| `/sports/*`, `/features/sports`, match lineups | Sports tables (admin) |
| `/catalog/version`, `/catalog/counts` | Local sync cursors + config version |
| `/me`, `/me/subscriptions`, `/profiles…`, favorites, history, my-list, continue-watching, reminders | Supabase Auth + user tables (RLS); local-only for guests |
| `/devices…`, `/auth/sessions…`, heartbeat, TV pairing (`/auth/device/code`) | Supabase tables + Edge Function (Phase 8) |
| `/playback/lease`, `/playback/report`, `/playback/active` | Not needed (direct provider URLs); progress → watch_history batches |
| `/notifications/*` | Notification center tables (Phase 9) |
| `/downloads/*`, quota | Entitlements (Phase 9) |
| `/auth/mfa/*`, `/parental-pin*` | Supabase Auth MFA; parental PIN local + synced setting |
| `/app/settings`, `/app/version`, signed config | `get_app_config` RPC (versioned) |

## Research notes (2026-11-14)
- Protocols: see `docs/PROVIDER_PROTOCOLS.md`. Third-party docs disagree on some
  parameter names (e.g. `series_id` vs `series`) → adapters must be tolerant and tested
  against real panels.
- Admin design references: official shadcn/ui dashboard blocks, "Next.js shadcn
  Dashboard Starter", "next-shadcn-admin-dashboard", Shadboard (sidebar + data tables +
  charts, dark/light, command palette). We build our own on shadcn blocks — no paid template.
- Next.js + Supabase security: per-request server client (RLS applies), `getUser()`
  not `getSession()` on the server, service role only in a `server-only` module,
  check auth + permission inside every server action, roles in `app_metadata`/tables.

## Log
- 2026-11-14 — Phase 0 done (planning files only, no code). Untested (nothing to run).
- 2026-11-14 — Step 1.1 done: admin scaffold + Supabase folder in `apps/admin`; build + redirect smoke test pass.
- 2026-11-14 — Step 1.2 done: identity/RBAC/audit migration live on Supabase; anon access denied everywhere (live check); TS types generated and wired into clients.
