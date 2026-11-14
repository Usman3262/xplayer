# XPlayer — change checklist

Every change made to turn the old CRUNCH 4K project into XPlayer, plus where to
change things from now on. Newest work at the top of each section.

Status words: **done** = changed in code; **analyzed** = `flutter analyze` has no
errors; **untested** = not run on a phone/TV yet.

---

## 1. Where to change things (quick map)

| What you want to change | Change it here | Then |
|---|---|---|
| App name (launcher, home screen, in-app text) | `app.config` → `APP_NAME` | `flutter clean`, rebuild |
| App ID (Android applicationId + iOS bundle id, phone + TV) | `app.config` → `APP_ID` | `flutter clean`, rebuild (a new ID = a new app on the device) |
| Apple signing team | `app.config` → `APP_DEVELOPMENT_TEAM` (or pick in Xcode) | rebuild |
| Logo / icons / splash / TV banner art | `tool/branding/make_xplayer_brand.py` (colours, sizes, shapes) | `python tool/branding/make_xplayer_brand.py` (needs Pillow) |
| Logo files used inside the app | `packages/design_system/assets/branding/xplayer_*.png/.svg` (keep names) | hot restart |
| Logo file names in code | `packages/design_system/lib/src/assets/app_assets.dart` | — |
| Theme colours (built-in defaults) | `packages/design_system/lib/src/theme/app_theme_config.dart` → `AppThemeConfig.defaults` | hot restart |
| Theme colours at runtime (admin panel later) | call `AppThemeConfig.applyJson({...})` | whole UI rebuilds |
| Colour token names used by screens | `packages/design_system/lib/src/theme/app_colors.dart` | — |
| Material theme (buttons, text styles) | `packages/design_system/lib/src/theme/app_theme.dart` → `buildAppTheme()` | — |
| Launcher icon background colour (Android) | `apps/*/android/app/src/main/res/values/colors.xml` → `ic_launcher_background` | rebuild |
| Backend API base URL | `packages/data/lib/src/remote/api_config.dart` → `defaultBaseUrl`, or `--dart-define=APP_API_BASE=https://host/v1` | rebuild |
| Self-hosted APK update links | `packages/data/lib/src/security/config_keys.dart` → `AppReleaseUrls` | rebuild |
| Signed remote-config keys / mirrors | `packages/data/lib/src/security/config_keys.dart` | rebuild |
| Android release signing | add `apps/<app>/android/key.properties` (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`) | otherwise release = debug key |
| Notifications from a new source | build a `PushMessage` and call `PushNotifications.show(msg)` (`apps/*/lib/core/push_notifications.dart`) | — |

---

## 2. Done

_(filled in below)_
