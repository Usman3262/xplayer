import 'dart:async';

import 'package:data/data.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/session_controller.dart';

/// Settings row: Active/Inactive · 1/1 from `GET /v1/playback/lease`.
class StreamSessionTile extends ConsumerStatefulWidget {
  const StreamSessionTile({super.key, required this.copy});

  final AppCopy copy;

  @override
  ConsumerState<StreamSessionTile> createState() => _StreamSessionTileState();
}

class _StreamSessionTileState extends ConsumerState<StreamSessionTile> {
  PlaybackLeaseStatusDto? _status;
  String? _deviceId;
  Object? _error;
  bool _loading = true;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    _poll = Timer.periodic(const Duration(seconds: 20), (_) {
      unawaited(_refresh(silent: true));
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final auth = ref.read(authRepositoryProvider);
      final media = ref.read(mediaRepositoryProvider);
      final deviceId = await auth.ensurePlaybackDeviceId();
      final status = await media.playbackLeaseStatus();
      if (!mounted) return;
      setState(() {
        _deviceId = deviceId;
        _status = status;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = widget.copy;
    final status = _status;
    String title = copy.streamSession;
    String subtitle = copy.streamSessionIdle;
    if (_loading && status == null) {
      subtitle = '…';
    } else if (_error != null && status == null) {
      subtitle = '—';
    } else if (status != null) {
      title = copy.streamSessionStatus(status.status, status.label);
      if (!status.isActive || status.playback == null) {
        subtitle = copy.streamSessionIdle;
      } else if (_deviceId != null &&
          status.playback!.deviceId == _deviceId) {
        subtitle = copy.streamingOnThisDevice;
      } else {
        subtitle = copy.streamingOnOtherDevice;
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          NeonGlowIcon(
            status?.isActive == true
                ? Icons.sensors_rounded
                : Icons.sensors_off_rounded,
            size: 24,
            color: status?.isActive == true
                ? AppColors.cyan
                : AppColors.textSecondary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: AppCopy.ofContext(context).refresh,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: () => unawaited(_refresh()),
            icon: const Icon(Icons.refresh_rounded, size: 20),
          ),
        ],
      ),
    );
  }
}
