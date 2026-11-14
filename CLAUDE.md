# XPlayer — rules for every Claude session

Personal project (not a team, not a client). Universal IPTV player: Flutter apps
(phone + Android TV) + Next.js admin panel + Supabase. Product spec:
`new-platform.md`. **Progress and next step: `ROADMAP_PROGRESS.md` — read it first,
update it last, every session.**

## 0. How we work
1. Read `ROADMAP_PROGRESS.md` before doing anything. Work on the **next unchecked
   step only** (or what the user asks). Small steps; never "everything at once".
2. After each step: tick it in `ROADMAP_PROGRESS.md`, add what was done, how it was
   tested, and what is next. Keep `XPLAYER_CHECKLIST.md` for app-level "where to
   change what".
3. Honest status words: *implemented* / *tested (how)* / *verified on a real
   device*. Emulator, unit test or sample data is not a device result. Untested =
   "untested". Never write "fixed" or "done" for something not run.
4. No Slack, no team posts, no external messages. Commit/push only when the user asks.
5. Ask the user only for real decisions (accounts, keys, product choices). Pick
   sensible defaults for the rest and write them in `ROADMAP_PROGRESS.md → Decisions`.

## 1. Repository
```
apps/mobile      Flutter phone app (Android + iOS)
apps/tv          Flutter Android TV app
apps/admin       Next.js admin panel (App Router, TS) — self-contained like its own repo
apps/admin/supabase  Supabase: migrations, seed, Edge Functions, RLS tests (CLI linked here)
packages/domain  pure Dart entities + contracts (no Flutter, no IO)
packages/data    data layer: providers (Xtream/M3U/Stalker), Supabase, cache
packages/design_system  theme tokens, shared widgets, brand assets
app.config       app name / app id / Apple team (single source)
```
Dependency direction: `apps → data → domain`, `apps → design_system → domain`.
Never import an app from a package. Mobile and TV share logic through packages.

## 2. No hard-coding — everything global and configurable
- **Name / ID**: only `app.config` (`APP_NAME`, `APP_ID`). In Dart use `AppBrand.name`.
- **Colours**: only `AppThemeConfig` / `AppColors`. No `Color(0xFF...)` in screens.
  New colour = new token in `AppThemeConfig` (+ admin field).
- **Text**: user-facing strings go through the locale layer (`AppCopy`/`app_locale`),
  never inline in widgets.
- **Remote-controllable behaviour** (home sections, banners, top 10, new/recent,
  matches & lineups, feature on/off, login policy, onboarding panel types, player
  defaults, cache policy, min app version, maintenance) comes from the **app config
  served by Supabase**, with a built-in default and the last good copy cached.
- **URLs, keys, limits, timeouts**: config or environment, never literals in code.
- Every feature the app has must be controllable from the admin panel. When you add
  an app feature, add its admin control (or a ticket in the roadmap) in the same step.
- Unknown/invalid remote config must never crash the app: validate, ignore bad
  fields, keep the last valid config.

## 3. Architecture rules
- Supabase is the only backend: Postgres, Auth, RLS, Storage, Edge Functions, Cron.
  No separate Node/Python server.
- **Video never goes through our backend.** The app plays directly from the user's
  provider. No proxy, no relay, no transcoding, no video in Storage.
- Provider adapters (Xtream, M3U, Stalker/MAC, future) implement one interface in
  `packages/data` and map into the existing `domain` entities (`MediaItem`,
  `LiveChannel`, `Episode`, `HomeFeed`…). Screens never know the protocol.
- Login is **optional** (guest mode by default). Admin decides the policy
  (`optional | required | disabled`). Guest data migrates to the account on sign-up.
- First launch flow: splash → *Choose your panel* (Xtream / M3U / Stalker-MAC …,
  list from admin config) → connect → home. Target: usable home in a few seconds
  (show cached data first, sync in background).
- TMDB (and any metadata API) is called **only server-side** (Edge Function with the
  key in Supabase secrets). Results are cached in the global catalog; the app never
  holds the TMDB key. Admin can override any field.
- Mobile + TV share packages; TV keeps its own D-pad UI, never a scaled phone UI.

## 4. Security rules
- RLS **on every table**, written in the same migration as the table. Default deny.
- Service-role key: only in Edge Functions and Next.js server-only modules
  (`import 'server-only'`). Never `NEXT_PUBLIC_*`, never in Flutter, never in git.
- Admin access = role + permission checked **in the database** (RLS / SECURITY
  DEFINER functions) and in every Next.js server action/route. UI hiding is not security.
  Roles live in tables / `app_metadata`, never in user-editable `user_metadata`.
- Every admin write goes through a server action/RPC that validates input (zod on
  web, SQL checks in DB) and writes an `audit_logs` row.
- Provider credentials (Xtream user/pass, MAC, tokens): stored on device in secure
  storage. If synced to cloud: encrypted (Supabase Vault/pgsodium) and never
  readable by admin queries. Never log credentials or full stream URLs.
- Clients cannot grant themselves plans, roles or entitlements; only trusted server code.
- No secrets in code, chat, commits or files. `.env*`, keys, keystores, and local
  tools with credentials (`neo-channel-tester.html`) are git-ignored.
- HTTPS for our backend. Cleartext allowed only for provider media (many providers are http).

## 5. Performance rules
### Supabase / SQL
- Select only needed columns (`select('id,title,poster')`), never `select(*)` in app code.
- Paginate everything (keyset/cursor on indexed columns; `range` only for small admin tables).
- Index every column used in `where`/`order by`/joins of hot queries; composite
  indexes match the real query. Check with `explain analyze` for new hot queries.
- One round trip per screen where possible: use RPC/views that return exactly what
  the screen needs (e.g. `get_app_config(platform, app_version)`, `get_home(...)`).
- Bulk upserts in batches; idempotent and resumable jobs with checkpoints.
- No per-second writes: batch playback progress (e.g. every 30 s + on pause/exit).
- Realtime only for small config/notification channels, never catalog tables.
- Version/ETag the app config so clients download it only when it changed.
### Flutter
- Cache-first: show local data instantly, refresh in background.
- Parse big playlists/JSON in isolates (`compute`/`Isolate.run`), never on the UI thread.
- Lazy lists (`ListView.builder`), fixed item extents where possible, image cache
  sized to display (`cacheWidth/Height`), skeletons instead of spinners.
- Parallel network calls for independent data (`Future.wait`), timeouts on every call,
  retries with backoff, cancellation when leaving a screen.
- Avoid rebuild storms: fine-grained Riverpod providers, `select`, `const` where the
  values are truly constant.
- Measure on a low-end Android TV box before calling something "fast".
### Next.js admin
- Server Components by default; client components only for interactivity.
- Data fetching on the server with the user's session (RLS applies); tables
  paginated server-side; debounce search; optimistic UI only with server confirmation.

## 6. Admin panel (Next.js) rules
- Next.js 16 App Router (`proxy.ts` = old middleware, Cache Components on: read cookies/session inside `<Suspense>`) + TypeScript (strict) + Tailwind 4 + shadcn/ui. Package manager: **npm**. Read `node_modules/next/dist/docs` when unsure — Next 16 differs from older docs.
- Next.js App Router + TypeScript (strict) + Tailwind + shadcn/ui. Dark-first, clean
  layout: sidebar modules, top bar, data tables, forms with zod, toasts, skeletons.
- Module per area (dashboard, users, providers, catalog, **app customization**,
  home builder, banners, sports, subscriptions, ads, notifications, devices,
  support, analytics, settings, audit). Each module guarded by a permission.
- Supabase types generated from the DB (`supabase gen types`) — the same contract
  for Next.js and Dart. Never invent a different meaning for a field.
- Preview + publish for app-facing config (draft → published version).

## 7. Database rules
- Every schema change = a migration in `apps/admin/supabase/migrations/` (never edit the DB by hand). Run Supabase CLI commands from `apps/admin`.
- Normalised tables; JSONB only for truly variable data (provider extras, section params).
- Every user-owned row has `user_id` (FK to `auth.users`) + RLS on it.
- `created_at`, `updated_at` on every table; soft-delete only where history matters.
- Retention jobs for logs/analytics. No unbounded tables.

## 8. Quality gates (before saying a step is done)
- `flutter analyze` + `flutter test` in each touched Dart package/app.
- `npm run lint && npm run typecheck && npm run build` (+ `npm test` once tests exist) in `apps/admin` when touched.
- RLS tests for every new table (`apps/admin/supabase/tests`).
- New code has tests for logic (parsers, adapters, mappers, entitlement checks).
- Update `ROADMAP_PROGRESS.md` (and `XPLAYER_CHECKLIST.md` if "where to change" moved).
