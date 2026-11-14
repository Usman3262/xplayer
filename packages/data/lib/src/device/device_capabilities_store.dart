import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../diag/diag.dart';
import 'device_capabilities.dart';

const kDeviceChannel = 'app/device';

/// Loads + caches device caps once per install (re-detect after app update).
class DeviceCapabilitiesStore {
  DeviceCapabilitiesStore._();
  static final instance = DeviceCapabilitiesStore._();

  DeviceCapabilities? _cached;
  TierMpvConfig? _mpv;

  DeviceCapabilities? get current => _cached;

  /// Operating system for the Control Panel customer details, e.g.
  /// "Android 14", "Android TV 11", "iOS 18.1". Null when unknown.
  Future<String?> osVersionLabel({bool tv = false}) async {
    try {
      if (Platform.isIOS) {
        final m = RegExp(r'(\d+(?:\.\d+)*)').firstMatch(Platform.operatingSystemVersion);
        return m == null ? 'iOS' : 'iOS ${m.group(1)}';
      }
      if (Platform.isAndroid) {
        final caps = await ensureLoaded();
        final release = caps.release.trim();
        final name = tv ? 'Android TV' : 'Android';
        return release.isEmpty || release == '?' ? name : '$name $release';
      }
    } catch (_) {}
    return null;
  }
  TierMpvConfig get mpv =>
      _mpv ?? TierMpvConfig.forTier(DeviceTier.mid);

  Future<DeviceCapabilities> ensureLoaded() async {
    if (_cached != null) return _cached!;
    final caps = await _detect();
    _cached = caps;
    _mpv = TierMpvConfig.forCapabilities(caps);
    // Startup diag prints once via logDeviceStartupDiag; avoid a duplicate [DEV].
    _applyImageCache(caps.tier);
    return caps;
  }

  void _applyImageCache(DeviceTier tier) {
    final mb = TierMpvConfig.forTier(tier).imageCacheMb;
    try {
      final cache = PaintingBinding.instance.imageCache;
      cache.maximumSizeBytes = mb * 1024 * 1024;
    } catch (_) {}
  }

  Future<DeviceCapabilities> _detect() async {
    // Platform throws on web (LG webOS build).
    if (kIsWeb || !Platform.isAndroid) {
      return const DeviceCapabilities(
        model: 'non-android',
        brand: '?',
        hardware: '?',
        socModel: '?',
        sdkInt: 0,
        release: '?',
        abis: [],
        totalRamMb: 4096,
        isLowRamDevice: false,
        screenWidthPx: 1080,
        screenHeightPx: 1920,
        density: 2,
        refreshRate: 60,
        hdr: false,
        codecs: {},
        tier: DeviceTier.mid,
      );
    }

    try {
      const ch = MethodChannel(kDeviceChannel);
      final raw = await ch.invokeMethod<Map<dynamic, dynamic>>('getCapabilities');
      if (raw == null) throw StateError('null caps');
      final m = Map<String, dynamic>.from(raw);
      final codecsRaw = m['codecs'];
      final codecs = <String, CodecMaxRes>{};
      if (codecsRaw is Map) {
        codecsRaw.forEach((k, v) {
          if (v is Map) {
            codecs['$k'] = CodecMaxRes.fromJson(Map<String, dynamic>.from(v));
          }
        });
      }
      final ram = (m['totalRamMb'] as num?)?.toInt() ?? 4096;
      final low = m['isLowRamDevice'] == true;
      final hevc = codecs['video/hevc'];
      final tier = DeviceCapabilities.computeTier(
        totalRamMb: ram,
        isLowRamDevice: low,
        hevc: hevc,
      );
      final caps = DeviceCapabilities(
        model: '${m['model'] ?? '?'}',
        brand: '${m['brand'] ?? '?'}',
        hardware: '${m['hardware'] ?? '?'}',
        socModel: '${m['socModel'] ?? '?'}',
        sdkInt: (m['sdkInt'] as num?)?.toInt() ?? 0,
        release: '${m['release'] ?? '?'}',
        abis: (m['abis'] as List?)?.map((e) => '$e').toList() ?? const [],
        totalRamMb: ram,
        isLowRamDevice: low,
        screenWidthPx: (m['screenWidthPx'] as num?)?.toInt() ?? 0,
        screenHeightPx: (m['screenHeightPx'] as num?)?.toInt() ?? 0,
        density: (m['density'] as num?)?.toDouble() ?? 1,
        refreshRate: (m['refreshRate'] as num?)?.toDouble() ?? 60,
        hdr: m['hdr'] == true,
        codecs: codecs,
        tier: tier,
      );
      await _persistTier(tier);
      return caps;
    } catch (e, st) {
      Diag.err('device caps failed', e, st);
      return const DeviceCapabilities(
        model: 'unknown',
        brand: '?',
        hardware: '?',
        socModel: '?',
        sdkInt: 0,
        release: '?',
        abis: [],
        totalRamMb: 4096,
        isLowRamDevice: false,
        screenWidthPx: 1080,
        screenHeightPx: 1920,
        density: 2,
        refreshRate: 60,
        hdr: false,
        codecs: {},
        tier: DeviceTier.mid,
      );
    }
  }

  Future<void> _persistTier(DeviceTier tier) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('app_device_tier', tier.name);
    } catch (_) {}
  }
}
