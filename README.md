# XPlayer

Personal Flutter test app: media player for phone and Android TV.

| App | Path | Platforms |
|-----|------|-----------|
| Mobile | `apps/mobile` | Android + iOS |
| TV | `apps/tv` | Android TV / Fire TV (D-pad) |

Shared code: `packages/domain` (entities), `packages/data` (data layer),
`packages/design_system` (theme, widgets, assets).

## Rename the app

Edit **`app.config`** (repo root) → `APP_NAME = ...`, then `flutter clean` and rebuild.
That one value sets the Android launcher name (phone + TV), the iPhone home-screen
name, and in-app text (`AppBrand.name`).

## Run

```bash
flutter pub get              # once, at the repo root (Dart workspace)
cd apps/mobile && flutter run
cd apps/tv && flutter run -d <android-tv-device>
```

Release builds are signed with the debug key unless you add
`apps/<app>/android/key.properties` (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`).

## Spec

`new-platform.md` — product spec for the Supabase-based version.
