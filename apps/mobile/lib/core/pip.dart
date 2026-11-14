import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'remote_config.dart';

/// Picture-in-Picture (C8).
///
/// - **Android:** system PiP when leaving the app (MainActivity).
/// - **iPhone:** system PiP when leaving the app, showing our own player
///   (AppPip.swift): same stream, same connection, every format.
class AppPip {
  AppPip._();

  static const _channel = MethodChannel('app/pip');

  /// True while the app is shown in the small window.
  static final inPip = ValueNotifier<bool>(false);
  static bool _wired = false;

  /// iPhone: PiP is armed for the current player (native side ready).
  static bool iosArmed = false;

  /// iPhone PiP window: Play (true) / Pause (false).
  static void Function(bool playing)? onIosSetPlaying;

  /// iPhone PiP window: skip by this many milliseconds (+/-).
  static void Function(int deltaMs)? onIosSkip;

  static void _wire() {
    if (_wired) return;
    _wired = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onPipChanged':
          inPip.value = call.arguments == true;
        case 'pipSetPlaying':
          onIosSetPlaying?.call(call.arguments == true);
        case 'pipSkip':
          final ms = call.arguments;
          if (ms is int) onIosSkip?.call(ms);
      }
    });
  }

  /// [enabled] while a video plays.
  ///
  /// Android: [width] / [height] give the window shape.
  /// iPhone: [mpvHandle] is the player's handle (`Player.handle`); its
  /// picture goes into the PiP window.
  static Future<void> setAuto(
    bool enabled, {
    int width = 16,
    int height = 9,
    int? mpvHandle,
  }) async {
    if (kIsWeb) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;
    // Admin feature switch: never arm PiP when it's turned off.
    if (enabled && !RemoteConfigService.current.isEnabled('picture_in_picture')) enabled = false;
    _wire();
    var armed = false;
    try {
      final r = await _channel.invokeMethod<bool>('setAutoPip', {
        'enabled': enabled,
        'width': width <= 0 ? 16 : width,
        'height': height <= 0 ? 9 : height,
        'handle': ?mpvHandle,
      });
      armed = r == true;
    } catch (_) {}
    if (Platform.isIOS) iosArmed = enabled && armed;
    if (!enabled) inPip.value = false;
  }

  /// iPhone PiP button: shows the current player in the PiP window now.
  /// False when iOS cannot start PiP (e.g. switched off in Settings).
  static Future<bool> startIos() async {
    if (kIsWeb || !Platform.isIOS || !iosArmed) return false;
    if (!RemoteConfigService.current.isEnabled('picture_in_picture')) return false;
    try {
      return await _channel.invokeMethod<bool>('startPip') == true;
    } catch (_) {
      return false;
    }
  }

  /// iPhone: playback state for the PiP window (play / pause button, time
  /// bar). Sent on play / pause / seek and every few seconds.
  static Future<void> iosState({
    required bool playing,
    required Duration position,
    required Duration duration,
    required bool live,
  }) async {
    if (kIsWeb || !Platform.isIOS || !iosArmed) return;
    try {
      await _channel.invokeMethod<void>('pipState', {
        'playing': playing,
        'positionMs': position.inMilliseconds,
        'durationMs': duration.inMilliseconds,
        'live': live,
      });
    } catch (_) {}
  }
}
