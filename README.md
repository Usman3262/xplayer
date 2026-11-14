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
cd apps/mobile && flutter run --dart-define-from-file=../../env/app.json
cd apps/tv && flutter run -d <android-tv-device> --dart-define-from-file=../../env/app.json
```

Without the `--dart-define-from-file` flag the apps still run, on built-in defaults
(no admin config). Build release APKs the same way (`flutter build apk --dart-define-from-file=…`).

Release builds are signed with the debug key unless you add
`apps/<app>/android/key.properties` (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`).

## Plan

- `new-platform.md` — product spec (Supabase + admin panel + provider engine).
- `ROADMAP_PROGRESS.md` — what is done, what is next, what remains.
- `CLAUDE.md` — project rules (no hard-coding, security, performance).
- `docs/PROVIDER_PROTOCOLS.md` — Xtream / M3U / Stalker-MAC notes.
