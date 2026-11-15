# XPlayer

Personal Flutter test app: media player for phone and Android TV.

| App | Path | Platforms |
|-----|------|-----------|
| Mobile | `apps/mobile` | Android + iOS |
| TV | `apps/tv` | Android TV / Fire TV (D-pad) |

Shared code: `packages/domain` (entities), `packages/data` (data layer),
`packages/design_system` (theme, widgets, assets).

## Rename the app / change its ID

Edit **`app.config`** (repo root) → `APP_NAME`, `APP_ID`, `APP_DEVELOPMENT_TEAM`,
then `flutter clean` and rebuild. It sets the Android launcher name and
applicationId (phone + TV), the iPhone name and bundle id, and in-app text
(`AppBrand.name`).

Full list of what was changed and where to change everything else (logo, theme,
backend URL…): **[XPLAYER_CHECKLIST.md](XPLAYER_CHECKLIST.md)**.

## Run

```bash
flutter pub get              # once, at the repo root (Dart workspace)
cp env/app.example.json env/app.json   # once; fill in Supabase URL + publishable key
cd apps/mobile && flutter run -d <device>     # Supabase settings come from env/app.json automatically
cd apps/tv && flutter run -d <android-tv-device> --dart-define-from-file=../../env/app.json
```

**Phone:** the Android build copies `env/app.json` into the app (`assets/config/app_env.json`,
git-ignored), so a plain `flutter run` / `flutter build apk` has the Supabase settings. `env/app.json`
is git-ignored: **on every PC that builds the app, create it** (copy `env/app.example.json` and fill in
the Supabase URL + publishable key). Without it the app runs, but accounts and admin config are off
(log: `[BACKEND] NOT CONFIGURED`). `--dart-define-from-file=../../env/app.json` still works and wins.

Release builds are signed with the debug key unless you add
`apps/<app>/android/key.properties` (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`).

## Plan

- `new-platform.md` — product spec (Supabase + admin panel + provider engine).
- `ROADMAP_PROGRESS.md` — what is done, what is next, what remains.
- `CLAUDE.md` — project rules (no hard-coding, security, performance).
- `docs/PROVIDER_PROTOCOLS.md` — Xtream / M3U / Stalker-MAC notes.
