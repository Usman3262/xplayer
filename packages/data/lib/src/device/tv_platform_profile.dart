import 'package:flutter/foundation.dart';

/// What the TV app runs as. Defaults are Android TV / Fire TV; the Samsung,
/// LG and Windows builds (`platforms/`) set their own values at start-up,
/// before `runApp`.
abstract final class TvPlatformProfile {
  /// `platform` sent when this TV registers a device / signs in. The backend
  /// accepts ANDROID_TV, FIRESTICK, TIZEN, WEBOS, WINDOWS.
  static String backendPlatform = 'ANDROID_TV';

  /// Device name shown in Devices and the Control Panel (`<name> (<id>)`).
  static String deviceName = 'Android TV';

  /// Badge on the TV splash screen.
  static String splashBadge = 'ANDROID TV • FIRE TV';

  /// The player's "native" engine (video_player: ExoPlayer on Android,
  /// the Tizen player on Samsung, HTML5 video on LG) can be used.
  static bool nativeEngineAvailable =
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// media_kit / mpv runs here. False on Samsung and LG: the player then
  /// always uses the native engine and never falls back to mpv.
  static bool mpvAvailable = true;

  /// Slow TVs (LG webOS: the app runs in the TV's browser engine). True:
  /// no live preview on focus (a channel plays on OK only), instant scrolling
  /// and focus moves (no animations). Android TV keeps false.
  static bool lowPowerUi = false;

  /// Closes the app ("Exit the app?" → Exit). Null = Android's
  /// SystemNavigator.pop. A web app on LG cannot close itself that way; the
  /// LG build sets `window.close()` (client 26 Oct #9).
  static void Function()? exitApp;

  /// Windows desktop build: screens say "PC" / "this device" instead of TV
  /// wording ("LIVING ROOM TV", "TV Remote", "recommended for TV" …).
  /// Android TV and the other TV builds keep false: their texts are
  /// unchanged.
  static bool pc = false;

  /// "TV" on the TV builds, "PC" on Windows (for short labels).
  static String get deviceWord => pc ? 'PC' : 'TV';
}
