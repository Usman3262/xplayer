import 'package:flutter/services.dart';

/// Free and total space of the volume that holds the app's files (Android
/// StatFs, iOS volume capacity for important usage).
class DeviceStorage {
  const DeviceStorage({required this.freeBytes, required this.totalBytes});

  final int freeBytes;
  final int totalBytes;

  static const _channel = MethodChannel('app/device');

  /// Null when the platform cannot tell.
  static Future<DeviceStorage?> read() async {
    try {
      final m = await _channel.invokeMapMethod<String, Object?>('getStorage');
      final free = (m?['free'] as num?)?.toInt();
      final total = (m?['total'] as num?)?.toInt();
      if (free == null || total == null || total <= 0) return null;
      return DeviceStorage(freeBytes: free, totalBytes: total);
    } catch (_) {
      return null;
    }
  }
}
