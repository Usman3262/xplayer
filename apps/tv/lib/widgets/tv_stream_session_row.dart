import 'dart:async';

import 'package:data/data.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/tv_session.dart';
import 'focus_tile.dart';

/// TV Settings: Active/Inactive · 1/1 from `GET /v1/playback/lease`.
class TvStreamSessionRow extends ConsumerStatefulWidget {
  const TvStreamSessionRow({super.key, required this.copy});

  final AppCopy copy;

  @override
  ConsumerState<TvStreamSessionRow> createState() => _TvStreamSessionRowState();
}

class _TvStreamSessionRowState extends ConsumerState<TvStreamSessionRow> {
  PlaybackLeaseStatusDto? _status;
  String? _deviceId;
  bool _loading = true;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    _poll = Timer.periodic(const Duration(seconds: 20), (_) {
      unawaited(_refresh());
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final auth = ref.read(tvAuthRepositoryProvider);
      final media = ref.read(tvMediaRepositoryProvider);
      final deviceId = await auth.ensurePlaybackDeviceId(
        name: TvPlatformProfile.deviceName,
        platform: TvPlatformProfile.backendPlatform,
      );
      final status = await media.playbackLeaseStatus();
      if (!mounted) return;
      setState(() {
        _deviceId = deviceId;
        _status = status;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = widget.copy;
    final status = _status;
    var label = _loading && status == null
        ? '…'
        : (status == null
            ? '—'
            : copy.streamSessionStatus(status.status, status.label));
    var detail = copy.streamSessionIdle;
    if (status != null && status.isActive && status.playback != null) {
      detail = (_deviceId != null && status.playback!.deviceId == _deviceId)
          ? copy.streamingOnThisDevice
          : copy.streamingOnOtherDevice;
    }

    return FocusTile(
      borderRadius: 12,
      onTap: () => unawaited(_refresh()),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(
              status?.isActive == true
                  ? Icons.sensors_rounded
                  : Icons.sensors_off_rounded,
              color: status?.isActive == true
                  ? AppColors.cyan
                  : AppColors.textSecondary,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    copy.streamSession,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: status?.isActive == true
                      ? AppColors.cyan
                      : AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
