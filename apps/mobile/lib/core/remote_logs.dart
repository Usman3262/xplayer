import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:data/data.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backend.dart';
import 'remote_config.dart';

/// Uploads the app's important log lines to Supabase (`log_app_events`) so
/// problems on real devices can be read and tested remotely.
///
/// * Only tagged lines from `Diag.event` / `Diag.err` / crashes — already
///   scrubbed (no credentials, stream URLs, MACs).
/// * Buffered from the first line of start-up; sent every few seconds in
///   batches (≤100), and when the app goes to the background.
/// * Admin switch `diagnostics.remote_logs` (default on); the server also
///   rate-limits and prunes.
/// * Device id = a random id for this install (not a hardware id).
class RemoteLogs {
  RemoteLogs._();

  static const _maxBuffer = 400;
  static const _batch = 100;
  static const _every = Duration(seconds: 8);

  static final _buffer = <Map<String, String>>[];
  static Timer? _timer;
  static bool _sending = false;
  static String? _deviceId;
  static final String _session = _randomId(8);
  static String _version = '';
  static String _model = '';

  /// This install's id (shown in Settings → About for support).
  static String? get deviceId => _deviceId;

  /// Call first in main(): starts buffering immediately (uploads begin once
  /// the backend is ready).
  static Future<void> start({required String appVersion}) async {
    _version = appVersion;
    Diag.remoteSink = _add;
    try {
      final prefs = await SharedPreferences.getInstance();
      _deviceId = prefs.getString('xp.diag.device_id');
      if (_deviceId == null || !RegExp(r'^[a-z0-9]{8,64}$').hasMatch(_deviceId!)) {
        _deviceId = _randomId(16);
        await prefs.setString('xp.diag.device_id', _deviceId!);
      }
    } catch (_) {
      _deviceId = _randomId(16);
    }
    _captureCrashes();
    _timer ??= Timer.periodic(_every, (_) => flush());
  }

  /// Device model once known (DeviceCapabilities), for the log rows.
  static void setModel(String model) => _model = model;

  static void _add(String tag, String message) {
    _buffer.add({'t': DateTime.now().toUtc().toIso8601String(), 'tag': tag, 'msg': message});
    if (_buffer.length > _maxBuffer) _buffer.removeRange(0, _buffer.length - _maxBuffer);
  }

  static bool get _enabled => RemoteConfigService.current.boolSetting('diagnostics.remote_logs', true);

  /// Sends what's buffered. Never throws; failures keep the lines for later.
  static Future<void> flush() async {
    final client = Backend.client;
    if (_sending || client == null || _buffer.isEmpty || _deviceId == null) return;
    if (!_enabled) {
      _buffer.clear();
      return;
    }
    _sending = true;
    try {
      while (_buffer.isNotEmpty) {
        final part = _buffer.take(_batch).toList();
        await client.rpc('log_app_events', params: {
          'p_device': _deviceId,
          'p_session': _session,
          'p_platform': kIsWeb ? 'web' : (Platform.isIOS ? 'ios' : 'android'),
          'p_version': _version,
          'p_model': _model,
          'p_events': part,
        }).timeout(const Duration(seconds: 10));
        _buffer.removeRange(0, part.length);
      }
    } catch (e) {
      // Offline / server busy: keep the lines, try again on the next tick.
      // Printed only (not uploaded) so it can't loop.
      if (kDebugMode) debugPrint('[LOGS] upload failed, will retry: ${e.runtimeType}');
    } finally {
      _sending = false;
    }
  }

  static void _captureCrashes() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      Diag.event('CRASH', '${details.exception.runtimeType}: ${details.exceptionAsString()}'
          ' | ${_frames(details.stack)}');
      previous?.call(details);
    };
    final previousPlatform = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      Diag.event('CRASH', 'uncaught ${error.runtimeType}: $error | ${_frames(stack)}');
      return previousPlatform?.call(error, stack) ?? false;
    };
  }

  static String _frames(StackTrace? st) => (st?.toString() ?? '')
      .split('\n')
      .where((l) => l.contains('package:player_mobile') || l.contains('package:data'))
      .take(5)
      .map((l) => l.replaceAll(RegExp(r'\s+'), ' ').trim())
      .join(' ← ');

  static String _randomId(int n) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final r = Random.secure();
    return String.fromCharCodes(List.generate(n, (_) => chars.codeUnitAt(r.nextInt(chars.length))));
  }
}
