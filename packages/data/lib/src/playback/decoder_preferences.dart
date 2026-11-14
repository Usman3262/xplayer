import 'package:shared_preferences/shared_preferences.dart';
import 'decoder_mode.dart';

/// Non-sensitive local preference; applied on the next playback open.
abstract final class AppDecoderPreferences {
  static String _key({required bool tv}) =>
      tv ? 'app_decoder_tv_v1' : 'app_decoder_mobile_v1';

  static Future<AppDecoderMode> load({required bool tv}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return AppDecoderMode.fromKey(prefs.getString(_key(tv: tv)));
    } catch (_) {
      // Local preference failure must not block authenticated playback.
      return AppDecoderMode.auto;
    }
  }

  static Future<bool> nativeEngine({required bool tv}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // TV default: the Android engine (ExoPlayer). On TCL MT9689 mpv could
      // not decode to the surface ("Both surface and native_window are NULL")
      // and fell back to mediacodec-copy: dropped frames at 720p, lag on 4K.
      // mpv stays as a one-time fallback and a Settings choice. Mobile keeps
      // mpv. Key v2 resets older test choices.
      return prefs.getBool(tv ? 'app_native_tv_v2' : 'app_native_mobile_v1') ?? tv;
    } catch (_) { return tv; }
  }

  static Future<void> saveNativeEngine(bool enabled, {required bool tv}) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setBool(tv ? 'app_native_tv_v2' : 'app_native_mobile_v1', enabled)) {
      throw StateError('Could not save player selection');
    }
  }

  static Future<void> save(AppDecoderMode mode, {required bool tv}) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setString(_key(tv: tv), mode.key);
    if (!saved) throw StateError('Could not save decoder preference');
  }
}
