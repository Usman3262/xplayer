# XPlayer — roadmap & progress (read first, update last)

How to use: work on the **first unchecked step** (`[ ]`). When a step is finished,
tick it, write *how it was tested*, and move the "▶ NEXT" marker. Status words:
implemented / tested (how) / verified on device / untested.

Spec: `new-platform.md` · Rules: `CLAUDE.md` · App "where to change": `XPLAYER_CHECKLIST.md`
· Provider protocol notes: `docs/PROVIDER_PROTOCOLS.md`

---

## ▶ NEXT
**Phase 3 · Step 3.5 — Home builder** (the big one): sections list (drag/up-down order, on/off,
rename, type, layout, source: auto / panel newest / panel rating / panel category / manual picks /
random / watch stats, params like days, limit, targeting platform/country/login, schedule) with a
preview using the **app's existing home look** (D17). Then 3.6 Banners, 3.7 Top 10.

## Waiting on you
- [ ] Add **`TMDB_API_KEY`** as a Supabase Edge Function secret (needed at step 1.7).
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
- [ ] 3.5 Home builder: add/remove/reorder/rename sections, source = auto / manual pick /
  random / TMDB trending, targeting, schedule, preview (phone + TV), publish.
- [ ] 3.6 Banners (hero carousel): image, title, deep link, schedule, targeting.
- [ ] 3.7 Top 10 lists (manual / auto from analytics / TMDB trending), per country/platform.
- [ ] 3.8 "New" / "Recently added" rules (provider added date, TMDB release, manual).
- [ ] 3.9 Sports: matches, lineups, competitions, which channel shows a match.
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
- 2026-11-14 — Phase 0 done (planning files only, no code). Untested (nothing to run).
- 2026-11-14 — Step 1.1 done: admin scaffold + Supabase folder in `apps/admin`; build + redirect smoke test pass.
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
