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

### 2.1 Project clean-up (round 1)
- [x] Deleted other platforms: `platforms/` (Windows, Tizen, webOS, LG web, Samsung web, common).
- [x] Deleted desktop/web runners inside `apps/mobile`: `linux/`, `macos/`, `web/`, `windows/`.
- [x] Deleted `docs/`, `.cursor/`, `.vscode/`, `.github/`, `releases/`, `scripts/`, `signing/`, old root `tool/`, `DEVELOPER_NOTES_*.md`.
- [x] Deleted team `CLAUDE.md` (Slack posting rules) — no Slack posts from this project. A new personal `CLAUDE.md` (project rules) was written later; progress lives in `ROADMAP_PROGRESS.md`.
- [x] Deleted `.env` (old backend key, unused by the app).
- [x] Deleted `third_party/media_kit_video` fork + its `dependency_overrides` in root `pubspec.yaml` (uses pub.dev `media_kit_video` now).
- [x] Deleted package/app boilerplate READMEs, LICENSE stubs, package CHANGELOGs.
- [x] Deleted `apps/tv/tool/` and `packages/design_system/tool/` (old icon/avatar helpers).
- [x] Deleted iOS `ExportOptions-*.plist` (old App Store export).
- [x] New `README.md`, new `.gitignore` (no team/signing paths; ignores keys, `.env`).
- [x] Kept: `new-platform.md` (your Neo/Supabase spec), `devtools_options.yaml`.

### 2.2 App name from one place
- [x] `app.config` (repo root, xcconfig format) holds `APP_NAME`, `APP_ID`, `APP_DEVELOPMENT_TEAM`.
- [x] Android (phone + TV): `apps/*/android/app/build.gradle.kts` reads `app.config` → `manifestPlaceholders["appName"]` → `AndroidManifest.xml` `android:label="${appName}"`.
- [x] iOS: `apps/mobile/ios/Flutter/Debug.xcconfig` + `Release.xcconfig` `#include "../../../../app.config"` → `Info.plist` `CFBundleDisplayName` / `CFBundleName` = `$(APP_NAME)`.
- [x] Dart: `AppBrand.name` (`packages/domain/lib/src/brand/app_brand.dart`) is set in each `main()` from the native launcher name (`PackageInfo.appName`) — so it also follows `app.config`.
- [x] ~140 in-app texts (EN/AR/UR) that said "CRUNCH 4K" now use `AppBrand.name` (titles, about, legal, notifications, errors, MFA issuer, MaterialApp title…).
- [x] Android playback notification ("Playing on …") uses the launcher label.
- [x] `design_system` now depends on `domain` (for `AppBrand`).

### 2.3 App ID / bundle ID from config (`com.crunch4k.app` removed)
- [x] Android `applicationId = appId` from `app.config` (`APP_ID = com.xplayer.app`) — phone and TV share it (as before).
- [x] iOS `PRODUCT_BUNDLE_IDENTIFIER = "$(APP_ID)"` (Runner); RunnerTests = `com.player.RunnerTests`.
- [x] iOS `DEVELOPMENT_TEAM = "$(APP_DEVELOPMENT_TEAM)"` (old company team id removed).
- [x] iOS signing switched to **Automatic** + "Apple Development"; old "CRUNCH4K App Store" provisioning profile removed.
- [x] Android namespaces (internal, not user-visible): `com.player.mobile`, `com.player.tv`; Kotlin moved to `kotlin/com/player/{mobile,tv}/`.
- [x] Platform channel names: `com.crunch4k.app/*` → `app/*` (device, pip, screen_secure, device_binding, token_vault, app_update) — Dart, Kotlin and Swift match.
- [x] Keystore aliases / prefs / wake-lock / notification-channel ids renamed `crunch4k.*` / `c4k_*` → `app.*` / `app_*`.
- [x] FileProvider authority `${applicationId}.appupdate`, `res/xml/app_update_paths.xml`.

### 2.4 Firebase removed completely
- [x] `firebase_core`, `firebase_messaging` removed from both app pubspecs.
- [x] `google-services.json` (phone + TV) and `GoogleService-Info.plist` deleted; plist removed from Xcode project.
- [x] `com.google.gms.google-services` Gradle plugin removed (settings + app).
- [x] Firebase `<meta-data>` removed from both `AndroidManifest.xml`.
- [x] iOS: `FirebaseAppDelegateProxyEnabled`, `remote-notification` background mode and `aps-environment` entitlement removed; `Podfile.lock` deleted (regenerates on `pod install`).
- [x] `push_notifications.dart` (phone + TV) rewritten: local notifications only (tray, channels, permission, tap routing, unread badge). Same public API (`start`, `onAppResumed`, `refreshUnread`, `syncToken` = no-op, `osAllowsNotifications`, `openOsNotificationSettings`).
- [x] New provider-neutral `PushMessage` (`packages/data/lib/src/notifications/push_message.dart`) + `PushNotifications.show(msg)` for a future source (Supabase realtime, etc.).

### 2.5 All CRUNCH branding removed
- [x] New XPlayer artwork (original): red gradient "X" (#B3121F → #FF3B4A) with a white play triangle on near-black #0D0607; wordmark in Bebas Neue. (Was violet→cyan until 2026-11-15.)
- [x] Generator: `tool/branding/make_xplayer_brand.py` (Pillow). Re-run to regenerate everything.
- [x] `packages/design_system/assets/branding/`: old 15 files deleted; new `xplayer_mark.png/.svg`, `xplayer_wordmark.png`, `xplayer_lockup(.png|_rtl.png)`, `xplayer_launcher.png`, `xplayer_launcher_fg.png`, `xplayer_splash.png`.
- [x] Android (phone + TV, same names/sizes): launcher mipmaps, adaptive foregrounds, Android 12 splash (+ night), status-bar icon (white), notification badge, splash background, TV banners (4 sizes).
- [x] iOS: all 21 AppIcon sizes (no alpha), launch background.
- [x] `ic_launcher_background` = `#0B0B12` (was black); pubspec icon/splash configs point to `xplayer_*` files and `#0B0B12`.
- [x] Splash now uses `xplayer_mark.svg` directly (old precompiled `.svg.vec` gone).
- [x] Dart rename: every `Crunch*`/`crunch*`/`c4k*` identifier → `App*`/`app*` (e.g. `CrunchColors` → `AppColors`, `CrunchLogo` → `AppLogo`, `CrunchAppBar` → `MainAppBar`, `MyCrunchScreen` → `MyAccountScreen`, `Crunch4kApp` → `MobileRootApp`, `Crunch4kTvApp` → `TvRootApp`); 29 files renamed `crunch_*.dart` → `app_*.dart` (+ imports).
- [x] App package names: `crunch4k_mobile` → `player_mobile`, `crunch4k_tv` → `player_tv`; workspace `xplayer_workspace`.
- [x] Route `/my-crunch` → `/my-account`; storage keys `c4k.*` → `app.*` (fresh installs, nothing to migrate).
- [x] Removed company text ("CREATEEX Tech"), team names in config comments, old privacy-manifest header.
- [x] iOS native PiP (`CrunchPip.swift`, needed the deleted fork) removed; Dart side already ignores a missing channel → PiP simply off on iPhone. Android PiP unchanged.

### 2.6 Global theme (ready for the admin panel)
- [x] `AppThemeConfig` (`packages/design_system/lib/src/theme/app_theme_config.dart`): all colours in one object, `defaults` = XPlayer black & red palette (primary #E11D2E on #0D0607), `applyJson(map)` / `apply(config)` / `reset()`, `toJson()`, partial JSON allowed.
- [x] `AppColors.*` are now getters reading the current theme (names kept, plus `primary` / `secondary`).
- [x] Both app roots listen to `AppThemeConfig.revision` and rebuild the whole UI when the theme changes.
- [x] Default "Cinematic" appearance preset (phone + TV) follows the global theme; other presets (Midnight, Carbon, Deep Cinema) unchanged.
- [x] Hard-coded old brand colours (cyan `#00C8FF`, magenta `#FF2BD6`, …) replaced with theme tokens.
- [x] `const` widgets/values that used colours were made non-const (needed for runtime colours); constructor colour defaults moved to `x ?? AppColors.y`.
- [x] Theme preference key renamed `CRUNCH Cinematic` → `Cinematic`.

### 2.7 Backend / API (data shape kept, old server removed)
- [x] Kept the whole data layer (`packages/data`: repositories, DTOs, API clients, demo catalog) so Neo can feed the same screens/models.
- [x] `ApiConfig.defaultBaseUrl = ''` (old `api.sksj.online` removed); `ApiConfig.isConfigured`; set a backend with `--dart-define=APP_API_BASE=...`.
- [x] `ApiClient` fails fast with "No server is configured yet." when no base URL.
- [x] Signed remote-config keys and mirror URLs emptied (`config_keys.dart`) → feature off.
- [x] Self-hosted APK update links emptied (`AppReleaseUrls`) → in-app APK update off; version/settings fetch skip empty bases.
- [x] Old host removed from speed test and from `network_security_config.xml` (both apps).
- [x] Tests updated to the empty-backend values.

### 2.8 Android signing
- [x] Release builds use `apps/<app>/android/key.properties` if present, else the **debug key** (no more hard failure). `-PplayStore` still swaps in the Play manifest.

---

## 3. Verification
- `flutter analyze` (domain, data, design_system, mobile, tv): **0 errors** (only old style warnings/infos remain).
- `flutter test`: see section 5.
- **Untested on a real device**: Android phone, Android TV, iPhone. Not built yet (`flutter build apk` / Xcode not run).

---

## 4. Known gaps / to do next
- [ ] First real build on phone + TV (`flutter clean && flutter run`), check launcher name, icon, splash, theme colours.
- [ ] iOS: run `pod install`, pick your team in Xcode (or set `APP_DEVELOPMENT_TEAM`). App Attest entitlement (`com.apple.developer.devicecheck.appattest-environment`) is still in `Runner.entitlements` — remove it if your Apple account can't enable App Attest.
- [ ] iOS launch screen has no logo (Flutter splash animation shows it right after).
- [ ] Login/sign-up/catalog need the new backend (Neo + Supabase). Until then: "Try demo" shows the sample catalog.
- [ ] Server-dependent features currently off: push messages, in-app APK updates, signed remote config, device sessions, MFA, subscription info.
- [ ] Theme JSON is not yet fetched/cached from anywhere — wire `AppThemeConfig.applyJson` to Supabase (admin panel) and cache it locally.
- [ ] Legal texts (terms/privacy in `app_legal_copy.dart`, `app_locale.dart`) are the old wording with the new name — rewrite for XPlayer.
- [ ] Old-feature screens still present (sports match centre, clips, kids, TV pairing, Windows text in TV settings) — decide what to keep for Neo.
- [ ] Code comments still mention old dates / people in places (no effect on the app).

---

## 5. Test results (2026-11-14, Windows, `flutter test`, no device)

| Package | Result |
|---|---|
| packages/domain | 159 passed |
| packages/data | 264 passed |
| packages/design_system | 33 passed |
| apps/mobile | 20 passed |
| apps/tv | 45 passed |

Test changes made to get there:
- `packages/data/test/fixtures/signed_config_fixture.json` and `mirror_config_fixture.json` re-signed with a new **test-only** Ed25519 key (payload type is now `app.app-config`). Not a production key.
- Data tests that checked the old server URLs/keys now check that none are built in.
- Relative APK paths in `releases.json` are ignored when no download host is set (was producing `/x.apk`).
- Notification startup (phone + TV) no longer crashes the app if local notifications are unavailable; it logs and continues (the TV boot test failed on this).
