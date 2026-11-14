import '../device/device_storage.dart';
import '../remote/extras_api.dart';

/// Why a download cannot start or continue.
enum DownloadSpaceProblem { limitReached, deviceFull }

/// Download storage rules (client 17 Oct), the same on TV and phones:
/// - the customer's limit (default 10 GB, set per package on the server)
///   counts the downloads on all of the customer's devices;
/// - downloads never fill the device: at least [reserveBytes] stays free,
///   so the app and the system keep working.
class DownloadSpaceGuard {
  const DownloadSpaceGuard._();

  static const reserveBytes = 2 * 1024 * 1024 * 1024; // 2 GB

  /// Before a download starts or resumes ([remainingBytes] = what is still
  /// to be written, null when the size is not known yet).
  static DownloadSpaceProblem? check({
    required DownloadQuotaDto? quota,
    required DeviceStorage? storage,
    int? remainingBytes,
    int ownServerBytes = 0,
  }) {
    if (quota != null) {
      final others = quota.usedBytes - ownServerBytes;
      if (remainingBytes == null) {
        if (others >= quota.limitBytes) return DownloadSpaceProblem.limitReached;
      } else if (others + ownServerBytes + remainingBytes > quota.limitBytes) {
        return DownloadSpaceProblem.limitReached;
      }
    }
    if (storage != null) {
      final need = (remainingBytes ?? 0) + reserveBytes;
      if (storage.freeBytes < need) return DownloadSpaceProblem.deviceFull;
    }
    return null;
  }
}
