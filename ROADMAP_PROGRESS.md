# XPlayer — roadmap & progress (read first, update last)

How to use: work on the **first unchecked step** (`[ ]`). When a step is finished,
tick it, write *how it was tested*, and move the "▶ NEXT" marker. Status words:
implemented / tested (how) / verified on device / untested.

Spec: `new-platform.md` · Rules: `CLAUDE.md` · App "where to change": `XPLAYER_CHECKLIST.md`
· Provider protocol notes: `docs/PROVIDER_PROTOCOLS.md`

---

## ▶ NEXT
**Phase 5 · Step 5.2 — Xtream adapter (Neo):** `XtreamAdapter implements ProviderAdapter` in
`packages/data/lib/src/providers/xtream/` — login/account → `ProviderAccount`, categories, live/vod/series
lists, vod/series info, short EPG (base64), stream URL builder (output format from `player.live_format` +
`allowed_output_formats`), registered in `ProviderAdapterFactory`. Tests with recorded JSON fixtures.

## Waiting on you
- [ ] **Android build setup on this PC** (to run on your phone/TV): free ~10 GB, install Android Studio
  (SDK + adb), then I enable Android in Flutter, set the SDK path, fix `JAVA_HOME`, accept licences,
  build + install. Allow "USB debugging" on the phone when asked.
  Meanwhile: **browser preview** works — `cd apps/mobile; flutter run -d chrome --web-port 5555
  --dart-define-from-file=../../env/app.json`, then F12 → Ctrl+Shift+M (phone size). Screens only; IPTV
  video won't play in a browser (http streams). `apps/mobile/web/` exists only for this preview.
- [x] `TMDB_API_KEY` set as a Supabase secret (done by you; metadata-tmdb verified live).
- [ ] **Sports API**: which provider? (e.g. API-Football / football-data.org / TheSportsDB)
  — needed at step 3.9; key goes in Supabase secrets.
- [x] Super admin created by you (2026-11-15). Secret key added to `.env.local`. Root `supabase/` folder deleted.

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
| D13 | **Rails/Top 10 from the user's panel** (provider_added / provider_rating / provider_category / manual picks by panel id / random / watch_stats) — never TMDB lists | User decision 2026-11-15 |
| D14 | **No bulk import of panel catalogs** (Neo ≈ 60k movies + 70k series): app caches the panel catalog locally; TMDB metadata fetched on demand (visible/opened titles, batched ≤25, tmdb id first) and cached once for all users | User decision 2026-11-15; cost + speed |
| D15 | **Default theme black & red** (apps + admin), still changeable from admin; admin layout follows the user's reference dashboard (screenshot 2026-11-15; Figma links not readable by the connected Figma account) | User decision 2026-11-15 |
| D16 | Vercel functions pinned to **Tokyo `hnd1`** (Supabase region ap-northeast-1); auth = local JWT verification (`getClaims`) + one `admin_session()` DB call per request | Speed: was 5–6 trans-Pacific round trips per page |
| D17 | **Keep the current app UI design + architecture**; admin changes colours, flags, texts/images, rails, settings only. Flow: choose panel → credentials → Connect → home; account creation **optional, offered after connecting** (sync favorites/history/progress/settings) | User decision 2026-11-15 |
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
- [x] 1.3 Migration 002 `20261115000001_app_config.sql` — `app_settings` (typed + validated:
  bool/int/number/enum/color/url/string_list, min/max/options; 22 defaults incl. `auth.mode=optional`),
  `feature_flags` (25, platform/version/schedule; `push_notifications` **off**), `feature_overrides`
  (user/country/plan), `app_versions` (min/recommended per platform), `maintenance_windows`,
  `onboarding_panel_types` (xtream, m3u, stalker + form field definitions), `app_themes`
  (tokens = Flutter `AppThemeConfig`), `config_versions` (published snapshots).
  Functions: `publish_app_config(notes)` (needs `customization.publish`, audited),
  `get_app_config(platform, app_version, known_version)` (anon OK; returns evaluated flags,
  settings, version policy, active maintenance, onboarding list, theme; `{"unchanged":true}`
  when the app already has the version), `version_cmp()`, generic `audit_row_change()`
  trigger on all 7 config tables. Initial version 1 published.
  *Tested (live, as anonymous app):* config v1 returned (≈3 KB, 22 settings, 25 flags, 3 panel
  types, theme); known version → `unchanged`; bad platform → error; direct table reads and
  `publish_app_config` → 42501. *Not tested yet:* admin writes + setting validation +
  overrides (need a signed-in admin — step 2.1). Types regenerated.
- [x] 1.4 Migration 003 `20261115000002_home_builder.sql` — `home_sections` (17 types incl.
  hero_banners, continue_watching, top10, new_releases, recently_added, trending, popular,
  live_now, matches_live/upcoming, recommended, category, genre, collection, custom; sources
  auto / manual / random / tmdb_trending / tmdb_popular / tmdb_top_rated / provider_category;
  layouts rail/wide_rail/grid/hero/ranked/circles/cards; platform + country + login + schedule
  targeting), `home_section_items` (portable refs: TMDB id or title match, overrides),
  `banners` (phone + TV images, CTA, action content/category/screen/url), `top10_lists` +
  `top10_items`. Home is part of the published snapshot; `get_app_config` gained `p_country`
  and returns filtered `home`. 10 default sections (today's rails) + empty "Top 10 this week"
  list (filled by TMDB in 1.7). Published as config v2. Audit triggers on all 5 tables.
  *Tested (live, anonymous TV app):* v2 returns 10 sections in order, 0 banners, 1 top-10 list
  (≈5.8 KB); known version → `unchanged`; direct table reads → 42501. Types regenerated,
  `tsc` clean. *Not tested:* targeting by country/login/schedule (no such rows yet).
- [x] 1.5 Migration 004 `20261115000003_global_catalog.sql` — `global_movies`, `global_series`,
  `global_seasons`, `global_episodes`, `global_channels` (aliases, EPG id, quality), `genres`,
  `movie_genres`, `series_genres`, `countries`, `languages`. TMDB/IMDb ids, artwork paths,
  trailer key, rating, popularity, credits JSON, `locked_fields` (admin-edited fields are never
  overwritten by TMDB refresh), `is_published`, `metadata_source`. Trigram + popularity/date
  indexes. RLS: anon/signed-in read published rows; `catalog.write` to edit; service role for
  the TMDB job. RPC `search_catalog(q, kinds, max_results)` (typo-tolerant, ≤50). Audit trigger
  now skips non-user writes (migrations / service jobs) so TMDB syncs don't flood the log.
  *Tested (live):* service-key insert of a sample movie → generated year/title_norm OK; anon
  search "intersteler" → Interstellar (score 0.56); anon read OK; anon insert → 42501; sample
  deleted. Types regenerated. *Not tested:* unpublished rows hidden from anon, admin edits.
- [x] 1.6 Migration 005 `20261115000004_sports.sql` — `sports_competitions`, `sports_teams`,
  `sports_matches` (status/minute/score, featured, hidden), `sports_lineups` (players JSON),
  `sports_events`, `sports_standings`, `sports_match_channels` (global channel and/or name match
  for the user's panel), `sports_sync_state` (server only). Every synced row keeps
  `external_source/external_id` → any sports API can fill it. RPCs for apps:
  `get_matches(window live|upcoming|recent|today|all, competition, featured_only, limit)` and
  `get_match(id)` (match + lineups + events + channels, external ids stripped). RLS: apps read
  visible data; `sports.write` edits; audit on all tables.
  *Tested (live, sample data via service key, then deleted):* anon live list shows the match
  with score/minute/has_channels; match page returns lineup, goal event, channel; hiding the
  match → page `null` and lineups hidden for anon; anon insert → 42501. Types regenerated.
- [x] 1.7 Edge Function `metadata-tmdb` (`supabase/functions/metadata-tmdb/`: tmdb.ts client
  with retry/429, titles.ts cleaner + strict matcher, catalog.ts writers, index.ts router) +
  migration 006 `20261115000005_metadata_support.sql` (`metadata_misses`, `metadata_lists`,
  `metadata_sync_state`, settings `metadata.image_base_url/poster_size/backdrop_size/language/
  miss_retry_days`). Actions: `resolve` (apps, ≤25 items: tmdb id or messy panel title →
  catalog row; DB first, then TMDB; strict title+year match; misses cached 7 days), `season`
  (episodes, cached 7 days), `refresh` (admin), `lists` (admin/cron: trending/popular/top-rated
  for movies+series → `metadata_lists`, fetch missing titles, Top 10 from trending, republish
  config if Top 10 changed). Never overwrites `locked_fields`. `verify_jwt=false`; admin =
  user with `catalog.write` or the service/secret key. Deployed with `--use-api`.
  *Tested (live):* "EN - Interstellar (2014) 4K HEVC" → Interstellar 2014 (poster + trailer);
  "|EN| Breaking Bad" → series 2008; tmdb 27205 → Inception; nonsense title → null; repeat
  call 0.7 s (cached); season 1 of Breaking Bad → 7 episodes; anon `lists` → 401;
  `lists` with secret key → 6 lists × 20, 106 titles synced, Top 10 filled, config v4.
  *Not tested:* admin-user JWT path (needs admin login, step 2.1).
  **Revised same day (user decision D13/D14):** removed the TMDB `lists` job and the
  `metadata_lists` table; Top 10/rails no longer use TMDB. Migrations 007–009
  (`…06_provider_sources`, `…07_banner_action_check`, `…08_panel_rails`): section sources are now
  auto / provider_added / provider_rating / provider_category / manual / random / watch_stats;
  Top 10 sources manual / provider_added / provider_rating / watch_stats (+ `params`); old TMDB
  Top 10 items deleted; `panel_item_id` + `panel_key` on section items, Top 10 items and banners
  (admin picks from a reference panel). Config v6 published.
  *Tested (live):* TMDB source rejected (23514); bad banner action rejected; content banner
  needs a ref and accepts a panel id; `lists` → unknown action; `resolve` tmdb 550 → Fight Club;
  config v6 shows Top 10 = provider_rating, new/recent rails = provider_added.
  Note: the ~109 titles pre-fetched by the old lists job stay in the catalog as harmless cache.
- [x] 1.8 DB contract. TS: `npm run db:types` → `apps/admin/src/lib/supabase/database.types.ts`
  (regenerate after every migration). Dart (`packages/data/lib/src/backend/`, exported from
  `data.dart`): `RemoteConfig` (settings typed getters, flags `isEnabled`, `authMode`,
  `VersionPolicy.check`, `MaintenanceNotice`, `PanelType`/`PanelField`, theme tokens, raw JSON
  for caching), `HomeLayout`/`HomeSection`/`ContentRef`/`HomeBanner`/`Top10List` (panel sources,
  panel ids), `FixtureSummary`/`FixtureDetail` (+ lineups, events, channels), `CatalogSearchHit`,
  `TitleMetadata` + `MetadataQuery` (≤25, tmdb id first), `EpisodeMetadata`, `ArtworkUrls`
  (from `metadata.*` settings), `compareAppVersion`. All lenient: bad/unknown fields dropped,
  unknown section types skipped, never throws. Names chosen to avoid clashes with old
  `AppConfig`/sports classes. No TMDB cron (metadata on demand).
  *Tested:* 12 unit tests incl. a **real** `get_app_config` reply (fixture
  `test/fixtures/app_config_tv.json`, v6) — all pass; `flutter analyze` on data lib clean;
  mobile/tv/design_system analyze: no errors (existing infos only).
  **Phase 1 complete.**

## Phase 2 — Admin panel base
- [x] 2.1 Admin sign-in: `/login` (shadcn card, email + password, server action `signIn` with
  zod, same error for wrong email/password, non-admins signed out again, safe `next` redirect),
  `signOut`, `/forbidden`. `src/lib/auth.ts`: `getAdmin()` (verified `getUser` + DB
  `my_permissions()`, cached per request), `requireAdmin()`, `requirePermission(perm)`,
  `actionGuard(perm)` for server actions, `safeNext()` (blocks open redirects).
  Live RLS script `supabase/tests/live_rls_check.py` (temporary plain + content-manager users).
  *Tested:* `tsc` + eslint clean; dev server: `/login` renders form, `/` and `/forbidden` → 307
  to login when signed out; **20/20 live signed-in checks pass** (plain user: no perms, own
  profile only, can't change status / self-promote / read config / publish / write audit;
  content manager: setting max + enum validation, valid save records `updated_by`, publish →
  apps see new value, no audit read, audit rows written, can't create roles; restored + temp
  users deleted). *Not tested:* signing in through the browser UI with your account — please try.
- [x] 2.1b + 2.5 My account + admin 2FA. DB (migration 015): `has_permission()` now requires an
  **aal2** session when the admin has a verified authenticator (DB-level, so a stolen password
  alone gets nothing); setting `admin.require_two_factor` (server-side, default off);
  `admin_security_state()`. App: `getAdminGate()` (signed_out / not_admin / mfa_required /
  setup_2fa / ok) → `requireAdmin({next, allowWithout2fa})`, `actionGuard` refuses until the code
  is entered or 2FA is set up when required; sign-in sends 2FA admins to `/login/mfa` (6-digit
  code, "use a different account"); `/account`: set up 2FA (QR + manual key + code, cleans stale
  pending factors, turn off unless required), change password (current password verified with a
  throw-away client, ≥12 chars, audited `change_password`); "My account" in the profile menu.
  *Tested:* tsc + eslint clean; `supabase/tests/live_mfa_check.py` **10/10** (enroll + verify with
  computed TOTP; aal1 session → no permissions, aal2 → granted; fresh password-only sign-in denied;
  wrong code rejected); renders: `/account` (setup + password forms), `?setup=2fa` banner,
  `/login/mfa`; dev log 0 errors. Run Python checks with `PYTHONIOENCODING=utf-8` on Windows.
  *Not tested:* scanning the QR in a real app + the password change through the browser (please
  try); the `require_two_factor` redirect (turning it on would also affect your real account).
  **Recommended for you:** set up 2FA in My account, then turn on `admin.require_two_factor`
  (settings UI comes in Phase 3; meanwhile SQL: `update app_settings set value='true' where key='admin.require_two_factor';`).
- [x] 2.2 Admin layout + dashboard, styled after the user's reference (Payd-style dashboard:
  plain sidebar with collapsible groups, big search pill, bell, profile chip, greeting line +
  headline, very rounded cards, bar chart, donut, coloured mini-bars with legend, right rail with
  tabs + message cards) in **black & red**. Files: `src/config/nav.ts` (all 23 modules + permission,
  `ready` flag → "soon"), `components/layout/{app-sidebar,nav-search,user-menu,page-header}.tsx`,
  `components/states.tsx` (Empty/Error/Skeleton), `components/dashboard/rail.tsx`,
  `app/(dashboard)/{layout,page}.tsx`, `lib/dashboard-types.ts`; Toaster + TooltipProvider in root.
  DB: `admin_dashboard_stats()` (one call, `dashboard.read`, aggregates only, activity only with
  `audit.read`; migrations 010 + 012 weekly sign-ups). `getAdmin()` now calls `connection()`
  (fixes Next 16 "Date.now during prerender"). `use-mobile` hook rewritten with
  `useSyncExternalStore` (lint). `NEXT_PUBLIC_APP_NAME` env (no hard-coded brand).
  *Tested:* tsc + eslint clean; dev server: `/` → 307 signed out, `/login` 200, logo 200;
  **signed-in render** via `scripts/render_check.py` (temporary admin, deleted after): 200, greeting,
  chart, donut, catalog card, sidebar groups, "soon" items, activity tab present; dev log 0 errors.
  *Not tested:* how it looks in your browser (please check), mobile widths.
  *Moved to 2.3:* DataTable. *Later steps:* form kit + image upload (with the first forms, Phase 3).
- [x] 2.3 Audit log viewer `/audit` + shared table kit. DB (migration 013):
  `admin_audit_logs(limit, offset, action, entity, q, since)` (needs `audit.read`, returns actor
  email, filters, cap 101 rows) + `admin_audit_entities()`. Kit: `lib/table-params.ts` (URL state:
  page/size/q/filters, `withParams`, `sinceDaysIso`), `components/data-table/data-table.tsx`
  (server-rendered, exact total **or** cheap "has next page" via limit+1, empty state, pager),
  `components/data-table/toolbar.tsx` (debounced search + select filters in the URL, Clear).
  Page: When / Who / Action badge / What / Changes (field-level before → after diff, expandable;
  created/deleted/published summaries). Nav item enabled. Writes are audited by DB triggers +
  `log_audit()` (no app code needed).
  `scripts/render_check.py <path> <role> [texts…]` now generic (temp admin with any role).
  *Tested:* tsc + eslint clean; dev renders as temporary admins (all deleted): admin `/audit` 200
  with rows + diffs; `?action=publish` shows only publishes; `?page=2` pager; **content manager →
  redirect to /forbidden and no audit rows in the HTML**; dev log 0 errors.
  Note: Git Bash rewrites `/paths` in args → run scripts with `MSYS_NO_PATHCONV=1`.
- [x] 2.4 Admins & roles `/admins`. DB (migration 014): `admin_list_admins()`, `admin_set_role()`
  (one role per admin), `admin_set_active()`, `admin_remove()`, `admin_find_user()`; rules in the
  DB: can't change/deactivate/remove yourself, never remove/deactivate/demote the **last active
  super admin**; audit triggers on `admin_user_roles`, `admin_roles`, `admin_role_permissions`
  (audit entity id now also reads `user_id`). Server actions (`actions.ts`: zod + `actionGuard`
  + DB permission): add admin by email (existing account → role; new email → account created,
  **temporary password shown once**, `create_account` audited), change role, activate/deactivate,
  remove. UI: admins table (avatar, "(you)", role select, status, last sign-in, actions with
  confirm + toasts), Add-admin dialog with copy button, role cards with permissions by module.
  *Tested:* tsc + eslint clean; `supabase/tests/live_admin_mgmt_check.py` **13/13 pass** (find
  by email, one role, unknown role, no self-change/deactivate, content manager/anon refused,
  remove, audited); renders: super admin sees Add + controls, `admin` role sees list read-only,
  content manager → /forbidden; dev log 0 errors.
  *Not tested:* last-super-admin rule live (can't be triggered safely while your account is a
  super admin — logic reviewed); clicking the buttons in a browser (server actions run the same
  DB functions that were tested).

## Phase 3 — Admin "App Customization" tab
- [x] 3.0 Customization basics. DB (migration 017): `admin_config_status()` (live version vs draft,
  `changed` parts: settings/flags/versions/maintenance/onboarding/theme/home, `can_publish`);
  `publish_app_config()` now refuses empty publishes ("Nothing to publish") and trims notes; Storage
  bucket **`app-assets`** (public read, write = `customization.write`, PNG/JPG/WebP only — no SVG,
  2 MB max). Admin: `customization/layout.tsx` shows the **publish bar** on every customization page
  (green "Apps are up to date" / red "Unpublished changes: …", Publish dialog with note);
  `components/customization/image-upload.tsx` (browser → Storage, preview, remove);
  `lib/db-errors.ts` (safe messages); shadcn switch + textarea. Test helpers:
  `supabase/tests/_live.py` (temp users with role + TOTP aal2).
  *Tested:* `live_customization_check.py` **16/16** (status for CM, denied for analyst; toggle → dirty
  'flags'; analyst edit = 0 rows; bad platform rejected; toggle back → clean; empty publish refused;
  upload PNG + public read; analyst/plain/anon upload refused; SVG and >2 MB refused; delete).
- [x] 3.1 Branding & theme `/customization/theme`. Migration 018: settings `branding.display_name`,
  `branding.tagline`, `branding.logo_url`, `branding.splash_url` (public, empty = built-in).
  `lib/theme-tokens.ts`: the 13 tokens (**same keys as Flutter `AppThemeConfig`**), default black &
  red, 5 presets (Black & red, Midnight blue, Emerald, Royal purple, Gold on black), `normalizeTheme`,
  WCAG `contrast()`. Editor: grouped colour pickers + hex inputs, presets, reset, readability
  warnings (text/background, muted, white on primary), live **phone preview** (reference-style home:
  header, Go pro, red gradient Sport card, tile grid, LIVE row) + **TV preview**; branding card with
  name, tagline, logo + splash upload. Actions `saveTheme` (zod hex per token) / `saveBranding`
  (https only). Read-only roles see disabled controls.
  *Tested:* tsc + eslint clean; `live_theme_check.py` **10/10** (save theme → dirty 'theme', read-only
  role can't save, restore → clean; javascript: URL and wrong type rejected by DB; branding → dirty
  'settings', restore → clean); renders for content manager / marketing manager (disabled) /
  analyst (forbidden); dev log 0 errors.
  *App side pending (Phase 4):* Flutter must apply `theme` (AppThemeConfig.applyJson) and
  `branding.*` from `get_app_config`.
- [x] 3.2 Feature flags `/customization/flags`: card per flag with on/off switch (optimistic, toast
  "publish to send it"), badges (key, platforms, version range, schedule), edit dialog (name,
  description, platforms, from/up-to app version, turn on/off times), search + On/Off filter.
  Server actions `setFlagEnabled` / `updateFlag` (zod, version format, end > start, all/none
  platforms → null) + RLS. Fixed: publish bar needed `connection()` (Next 16 prerender).
  *Tested:* tsc + eslint clean; renders: content manager sees bar + switches + Publish, admin sees
  edit buttons, analyst → /forbidden; dev log 0 errors. *Not tested:* clicking in a browser.
- [ ] 3.2b Feature overrides UI (per user / country / plan) — DB + app config already support it.
- [x] 3.3 + 3.4 Login & panels `/customization/access`. Sign-in card: mode Optional / Required / Off
  (cards), guest use + new sign-ups switches with enforced combinations (required → no guest; off →
  guest only, no sign-ups; optional needs guest), panels per user, connect timeout (s → ms).
  "Choose your panel": list with on/off switch, move up/down (renumbers 10, 20, …), edit dialog
  (name, description, help text, platforms, per-field label/placeholder/required — field **keys and
  types are locked** because the app's provider code reads them), phone preview of the screen + the
  selected connect form. Migration 019: DB trigger keeps **at least one panel type enabled**.
  *Tested:* tsc + eslint clean; `live_access_check.py` **10/10** (disable one → dirty 'onboarding';
  disabling all refused by DB; read-only role can't edit; label/field edit; non-list fields refused;
  auth.mode accepted; >50 panels refused; all restored → clean); renders for content manager /
  marketing manager (no edit buttons) / analyst (forbidden); dev log 0 errors.
- [x] 3.5 Home builder `/customization/home`. `lib/home-sections.ts` = section types (17) with
  allowed sources / layouts / content kinds per type (mirrors DB checks + Dart enums), source params
  (days / match / min_rating). Actions: create / update (type-aware validation, params filtered to the
  source), on/off, move up/down/top/bottom (only changed rows written), delete, set manual picks
  (TMDB id / title match / panel id + panel key — **no hard-coded provider**). UI: numbered section
  list with badges (type, source, layout, picks, platforms, countries, signed-in, scheduled),
  add/edit dialog (only valid options per type, picks editor, platforms, countries, signed-in only,
  show from/until), phone/TV toggle **preview in the app's existing home style** (hero with VIP/4K,
  match cards, continue tiles with progress, ranked Top 10 numbers, channel circles, poster rails).
  *Tested:* tsc + eslint clean; `live_home_check.py` **23/23** incl. **end-to-end targeting via a
  real publish** (country ZZ hidden for others/shown for ZZ, signed-in only hidden for guests,
  next-year schedule hidden, picks with tmdb + panel id reach `get_app_config`, targeted config never
  answered "unchanged"), then test sections removed + republished (config v13 = same content as v11);
  direct rule checks of `config_item_visible` (platform, country incl. unknown, login, schedule);
  renders: content manager full builder, marketing manager read-only; dev log 0 errors.
  Note: in v12 one untargeted test section was briefly in the config (no app reads config yet);
  the test now targets every test section.
- [x] 3.6 Banners `/customization/banners`: cards with image preview, on/off, up/down, edit, delete;
  dialog with phone (16:9) + TV (21:9) image upload, title, subtitle, button text, action (image only /
  open a title by TMDB id or panel id + panel key / category / app screen / https link), shared
  **TargetingFields** (platforms, countries, signed-in only, from/until — `lib/targeting.ts` schema).
- [x] 3.7 Top 10 `/customization/top10`: lists with source (panel best-rated / panel newest / your
  ranking / most watched later), days + min rating, country, active; ranked 1–10 editor with reorder;
  "on home (n)" usage badge; Home builder Top 10 sections must pick a list (`top10_list_id`).
- [x] 3.8 "New / Recently added" rules — covered by Home builder sources (panel newest + "last N days")
  and Top 10 "panel newest".
- [x] 3.9 Sports `/sports` (manual until a sports API is chosen): match list (Live now / Today /
  Upcoming / Last 7 days, team search, pagination), match dialog (teams + competition by name — created
  if new, kickoff, status, score, minute, round, venue, featured, hidden, where-to-watch channel names,
  lineups as text "9 Name FW" + "subs", events "45+2 goal home Player (assist)"), competitions shown /
  featured toggles. Parsers in `lib/sports-parse.ts` with unit tests (`npm test`).
- [x] 3.11 Publish flow: draft → publish bar (3.0) + **Publish history** `/customization/history`
  (versions, notes, who, size, Live badge) + **emergency rollback** (`admin_republish_version`:
  republishes an old snapshot as a new version, drafts untouched; `_restored_from` ignored when
  comparing).
- [x] 3.2b Feature flag **exceptions** (per country / per signed-in user by email, optional schedule;
  user beats country) on the flags page (`admin_flag_overrides`, `admin_user_id_by_email`).
- [ ] 3.12 (later) "Pick from the reference panel": browse Neo in admin (credentials in Vault, server
  side) to choose banner/rail/Top 10 titles by panel id instead of typing ids.
- [ ] 3.13 (when chosen) Sports API sync job (Edge Function + cron) filling the same tables.

**Phase 3 complete (2026-11-15).** Milestone checks: `npm run lint` ✓, `typecheck` ✓, `npm test` ✓,
`npm run build` ✓ (17 routes); all 10 live suites **144 passed / 0 failed** (rls 20, admin mgmt 13,
mfa 12, security settings 5, customization 16, theme 10, access 10, versions 10, home 22, phase3 26);
renders by role for every page; dev log 0 errors. Migration 021 (`…20_phase3_completion`).
Live config content unchanged by tests (only hidden/identical test publishes, then republished).
*Not tested:* clicking through in a real browser (please try); `/sports` read-only view (no current
role has sports.read without sports.write).
- [x] 3.10 Versions & maintenance `/customization/versions`: version card per platform (minimum /
  recommended / latest, https update link, what's new; recommended ≥ minimum, latest ≥ recommended),
  maintenance list (Now / Scheduled / Finished / Off badges, on/off switch, delete) + "Schedule
  maintenance" dialog (title, message, start/end, platforms), Player + Cache & refresh cards built
  with the new generic **`SettingsCard`** (control chosen from the setting's type; min/max/options
  from the DB) + generic `saveSettings` action.
  **Security fix (migration 020):** settings in category `security` (e.g. `admin.require_two_factor`)
  now need `settings.write` (Admin/Super Admin), not just `customization.write`; adding/removing
  settings needs `settings.write`; key/category/type can't be changed via the API.
  *Tested:* tsc + eslint clean; `live_security_settings_check.py` **5/5**; `live_versions_check.py`
  **10/10** (versions → dirty, non-https link / end-before-start / retry>10 / bad live format
  rejected by DB, read-only role can't edit, restored → clean; nothing published); renders for
  content manager and marketing manager (no edit controls); dev log 0 errors.
- [ ] 3.11 Publish flow: draft → preview → publish (bumps config version, app refreshes).

## Phase 4 — Flutter: Supabase + remote config
- [x] 4.1 `supabase_flutter ^2.18.3` in mobile + TV; `core/backend.dart` (URL + **publishable** key from
  `--dart-define-from-file=../../env/app.json`; `env/app.json` git-ignored, `env/app.example.json`
  committed; not configured → app runs on built-in defaults; init never throws).
- [x] 4.2 `RemoteConfigRepository` (`packages/data`, backend-agnostic via injected fetcher): cached
  last-valid config applied **before the first frame**, background refresh with known version
  ("unchanged" = tiny reply), invalid/timeout/offline → keep last config, never goes backwards, one
  request at a time, auto-refresh every `config.refresh_interval_s` + on app resume. App side
  `core/remote_config.dart` (phone reports android/ios, TV reports tv; device country hint): applies
  theme (`AppThemeConfig.applyJson`) + `branding.display_name` (`AppBrand.setDisplayOverride`, launcher
  name unchanged); `remoteConfigProvider` + `featureEnabledProvider(flag)` for screens (unknown flags
  default on); root rebuilds on new config. Wired into both `main()`s. **No screen redesign.**
  *Tested:* analyze clean for new files (phone + TV); `remote_config_repository_test.dart` **7/7** incl.
  **LIVE** call to the real `get_app_config` (v15 config, panel types, home, auth mode; second call →
  unchanged). *Not tested:* running on a device/emulator; APK build with the new plugin (do at Phase 4
  milestone).
- [x] 4.3 Feature switches applied in the **existing** screens (no redesign): phone bottom bar + TV nav
  hide Movies / Series / Live TV / Sports / Kids when off (`sportsEnabledProvider` now = admin flag);
  router guard `featureOffRedirect` (phone + TV) sends any page of a switched-off feature Home
  (movies, series, live, sports, match centre, kids, clips, downloads/offline, search, inbox, my list,
  diagnostics, appearance, parental — exact prefix match); top-bar search + inbox icons, settings
  tiles (diagnostics, appearance, parental), trailer buttons (phone + TV) and picture-in-picture
  follow their flags; admin logo (`branding.logo_url`) replaces the built-in logo in the same spot
  (`AppLogo.remoteUrl`, built-in art as placeholder/fallback).
- [x] 4.4 Gates: `checkAppUpdate()` (phone + TV, used by the existing splash/update screens) now reads
  the admin **version policy** (minimum → must update, recommended → suggested; link + notes) instead
  of the old server; **MaintenanceGate** (phone + TV) shows the admin's maintenance title/message in
  the app's own colours with "Try again", lifts itself when the window ends.
  *Tested:* analyze clean for changed files (no new errors in either app); phone **26/26**, TV **51/51**
  tests (incl. 3 maintenance-gate widget tests + 3 route-guard tests per app).
- Phase 4 milestone (2026-11-15): package tests domain **159** / data **283** / design_system **33**
  pass; phone 26 / TV 51 pass. **APK builds and on-device run NOT done: this PC has no Android SDK**
  (Flutter has Android disabled — `no-enable-android`; no `adb`; only 3.4 GB free on C:; `JAVA_HOME`
  points to missing `E:\java.xml\jbr`). Needs Android Studio/SDK (~8–10 GB) before device testing.
- [→] Sign-in (old 4.3 "optional sign-in/up with Supabase Auth") **moved to Phase 5.7**, right after
  the panel connection, matching the flow "choose panel → connect → optional account" (D17).

## Phase 5 — Provider engine ("Choose your panel")
- [x] 5.1 `ProviderAdapter` interface + unified models + error/status model (spec §3.5).
  *Implemented* in `packages/data/lib/src/providers/`:
  - `provider_models.dart`: `ProviderKind` (keys match admin panel types), `ConnectionStatus` (all 11
    §3.5 states), `ProviderFailure`(+kind → status, retryable), credentials (Xtream / M3U / Stalker) with
    instant local validation, URL normaliser (`parsePanelUrl`), MAC normaliser, storage map, `toString`
    without secrets; `ProviderAccount` (expiry, max connections, formats), `ProviderCapabilities`,
    `StreamRef` → `ResolvedStream` (URLs with credentials built only at play time), channel/movie/series/
    episode/details/EPG models.
  - `provider_adapter.dart`: the interface + `ProviderAdapterFactory` (validates, `unsupported` for kinds
    not registered yet).
  - `provider_http.dart`: `ProviderLimits.fromConfig` (admin settings `providers.connect_timeout_ms`,
    `providers.request_timeout_ms`, `providers.request_concurrency`, clamped), `ProviderHttp` (timeout on
    every call, short login timeout, retries + backoff only for network/timeout/5xx/429, per-panel
    concurrency cap, JSON ≥256 KB decoded in an isolate, HTTP codes → failure kinds incl. 884/512 banned,
    errors never contain URLs).
  - `provider_mappers.dart`: → existing `CatalogCategory`, `LiveChannel` (EPG now/next/progress),
    `MediaItem`, `Episode` (same label helpers as before; no stream URLs stored).
  - Admin: Versions page → new **Panel connections** card (request timeout, parallel requests). Login
    timeout + panel limit were already under Access.
  *Tested:* `flutter test test/providers` 21/21 + mpv tests (split check) 7/7; `flutter analyze` on touched
  files: no errors. Admin `tsc` **not run** (`apps/admin/node_modules` missing — run `npm install` later).
- [ ] 5.2 Xtream adapter (auth/account info, categories, live/vod/series, series info,
  vod info, short EPG / xmltv, URL builder, output format choice). Tests with recorded JSON.
- [ ] 5.3 M3U adapter (URL/file, EXTINF attrs, groups, tvg-id, isolate parser, dedupe).
- [ ] 5.4 Stalker/MAC adapter (handshake/token, profile, genres, channels, VOD, create_link,
  token renew). Tests.
- [ ] 5.5 Connection manager: multiple panels, secure storage, test connection, status,
  expiry, primary, enable/disable, last sync.
- [ ] 5.6 Onboarding UI (phone + TV): choose panel → form → test → connect in seconds
  (account check first, catalog in background, cache-first) — using the app's existing look.
- [ ] 5.7 Optional XPlayer account after connecting (Supabase Auth: sign up / sign in, policy from
  `auth.mode`, guest data kept on device and synced after sign-up).

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
| Missing metadata (posters, cast, backdrops, trailers) — app used to call TMDB | `metadata-tmdb` `resolve` on demand → global catalog (cached once for all users) |
| `/catalog/top10` | `top10_lists` via app config: panel rating / panel newest / admin picks / watch stats (no TMDB lists) |
| Home rails (new, recent, trending…) | `home_sections` computed on device from the user's panel (provider_added / rating / category), admin picks, random |
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
- 2026-11-15 — Step 5.1 done: provider engine interface/models/HTTP/mappers + 21 tests; admin Panel connections card (tsc not run).
- 2026-11-15 — Browser preview of the mobile app: added `apps/mobile/web/`; split mpv FFI code into `mpv_native_ffi.dart` + web stub (conditional import); browser HTTP client in `api_client.dart`; web guard in `network_diag.dart`. Tested: app starts in Chrome (user ran it). Not a device result.
- 2026-11-14 — Phase 0 done (planning files only, no code). Untested (nothing to run).
- 2026-11-14 — Step 1.1 done: admin scaffold + Supabase folder in `apps/admin`; build + redirect smoke test pass.
- 2026-11-15 — Steps 4.3 + 4.4 done: feature switches, route guard, update + maintenance gates, remote logo; phone 26 / TV 51 tests.
- 2026-11-15 — Steps 4.1 + 4.2 done: Supabase client + cache-first remote config in both apps; 7/7 tests incl. live server.
- 2026-11-15 — **Phase 3 complete**: Banners, Top 10, flag exceptions, Sports, publish history + rollback; full milestone checks green (build + 144/144 live).
- 2026-11-15 — Step 3.5 done: Home builder (types/sources/layouts, picks, targeting, schedule, app-style preview); 23/23 live incl. end-to-end targeting.
- 2026-11-15 — Step 3.10 done: Versions & maintenance + generic SettingsCard; security-settings permission fix (migration 020); 15/15 live checks. Recorded D17 (keep current app UI; panel → connect → optional account).
- 2026-11-15 — Steps 3.3 + 3.4 done: Login & panels page (sign-in policy, Choose-your-panel editor + preview, DB guard); 10/10 live checks.
- 2026-11-15 — Step 3.1 done: Branding & theme editor with live phone/TV preview; 10/10 live checks.
- 2026-11-15 — Steps 3.0 + 3.2 done: publish bar + image storage + feature flags page; 16/16 live checks.
- 2026-11-15 — Speed fix (live site slow): measured 1.6–2.8 s per signed-in page on Vercel. Causes: Supabase in Tokyo (ap-northeast-1) while Vercel functions run in the US by default, and 5–6 sequential Supabase round trips per page. Fixes: `apps/admin/vercel.json` regions `hnd1` (Tokyo, same as Supabase); `getClaims()` (local ES256 JWT verification, no Auth round trip) in proxy + `getAdminGate`; migration 016 `admin_session()` = 2FA state + permissions in ONE call (was 2). Now ~2 round trips per page. Verified: tsc/eslint clean, MFA live check 12/12, page renders for 3 roles. **Deployed by you (pushed to main); live re-measure with a temporary 2FA admin: 0.60–0.77 s total, TTFB ≈0.25 s (was 1.6–2.8 s).** Render check now enrolls TOTP (you enabled `admin.require_two_factor`). Further option if ever needed: Supabase project in Mumbai (ap-south-1) + functions in bom1 (requires a new project + migration).
- 2026-11-15 — Step 2.5 done: My account (password) + admin 2FA enforced in the DB; 10/10 live MFA checks. Phase 2 complete.
- 2026-11-15 — Step 2.4 done: admins & roles page + safety rules in DB; 13/13 live checks, 3-role render check.
- 2026-11-15 — Step 2.3 done: audit log page + reusable DataTable/toolbar; permission + no-leak checks pass.
- 2026-11-15 — Black & red default theme (Flutter defaults, published config v9, admin CSS, regenerated red icons). Step 2.2 done: admin layout + dashboard in the reference style; signed-in render verified with a temporary admin.
- 2026-11-15 — Step 2.1 done: admin sign-in + guards; 20/20 live signed-in RLS checks pass.
- 2026-11-15 — Step 1.8 done: Dart contract models + 12 tests (real config fixture). Phase 1 complete.
- 2026-11-15 — Step 1.7 revised: Top 10/rails from the panel, TMDB on demand only (migrations 007–009, function redeployed, config v6).
- 2026-11-15 — Step 1.7 done: metadata-tmdb deployed; resolve/season/lists verified live; catalog seeded (51 movies, 58 series), Top 10 live.
- 2026-11-15 — Step 1.6 done: sports schema + get_matches/get_match live; visibility rules verified.
- 2026-11-15 — Step 1.5 done: global catalog + trigram search live; read/deny + typo search verified.
- 2026-11-15 — Step 1.4 done: home builder tables in the published config (v2); anon checks pass.
- 2026-11-15 — Step 1.3 done: app config tables + publish/snapshot + `get_app_config` live; anon checks pass.
- 2026-11-14 — Step 1.2 done: identity/RBAC/audit migration live on Supabase; anon access denied everywhere (live check); TS types generated and wired into clients.
