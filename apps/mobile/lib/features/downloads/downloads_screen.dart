import 'dart:async';

import 'package:data/data.dart'
    show DeviceStorage, DownloadQuotaDto, ExtrasApi, ProfileDownloadDto;
import 'package:design_system/design_system.dart';
import 'package:domain/domain.dart'
    show TransferRate, cleanDisplayName, formatBytes;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/downloads_controller.dart';
import '../../core/providers.dart' show deviceInternetProvider;
import '../../core/session_controller.dart';
import '../../widgets/main_app_bar.dart';

/// Offline downloads: queue, progress with file size, pause / resume /
/// retry / remove, and offline playback of finished files.
class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = AppCopy.ofLanguage(
      ref.watch(sessionProvider.select((s) => s.language)),
    );
    final items = ref.watch(appDownloadsProvider);
    final offline = ref.watch(sessionProvider.select((s) => s.offline));
    final notifier = ref.read(appDownloadsProvider.notifier);
    final header = Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            copy.downloads,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          _StorageLine(
            copy: copy,
            extras: ref.read(mediaRepositoryProvider).extras,
            reconcile: notifier.reconcileWithServer,
          ),
        ],
      ),
    );
    // The profile's downloads on its other devices (client 12 Nov #6/#7,
    // Usman 13 Nov): shown under this device's, with "Download here".
    final list = ValueListenableBuilder<List<ProfileDownloadDto>>(
      valueListenable: notifier.profileDownloads,
      builder: (context, _, _) {
        final others = offline ? const <ProfileDownloadDto>[] : notifier.otherDevices();
        if (items.isEmpty && others.isEmpty) {
          return AppEmpty(
            title: copy.downloadsEmpty,
            subtitle: copy.downloadsEmptyHint,
            icon: Icons.download_rounded,
          );
        }
        final rows = <Widget>[
          header,
          if (others.isNotEmpty && items.isNotEmpty) _SectionTitle(copy.downloadsOnThisDevice),
          for (final d in items) _DownloadTile(d: d, copy: copy),
          if (items.isEmpty)
            Text(copy.downloadsEmpty,
                style: TextStyle(color: AppColors.textSecondary)),
          if (others.isNotEmpty) ...[
            _SectionTitle(copy.downloadsOnOtherDevices),
            for (final r in others)
              _OtherDeviceTile(
                r: r,
                copy: copy,
                onDownload: () => notifier.enqueueFromOtherDevice(r),
              ),
          ],
        ];
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          itemCount: rows.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (_, i) => rows[i],
        );
      },
    );
    return Scaffold(
      appBar: const MainAppBar(showBack: true),
      body: offline
          ? Column(
              children: [
                _OfflineBanner(copy: copy),
                Expanded(child: list),
              ],
            )
          : list,
    );
  }
}

/// Free space on the device, refreshed every 10 s while the screen is open.
class _StorageLine extends StatefulWidget {
  const _StorageLine({required this.copy, required this.extras, this.reconcile});

  final AppCopy copy;
  final ExtrasApi extras;
  final Future<void> Function()? reconcile;

  @override
  State<_StorageLine> createState() => _StorageLineState();
}

class _StorageLineState extends State<_StorageLine> {
  DeviceStorage? _storage;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    unawaited(_read());
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _read());
  }

  DownloadQuotaDto? _quota;

  Future<void> _read() async {
    final s = await DeviceStorage.read();
    if (mounted) setState(() => _storage = s);
    await widget.reconcile?.call();
    final q = await widget.extras.downloadQuota();
    if (mounted) setState(() => _quota = q);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _storage;
    final q = _quota;
    if (s == null && q == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        [
          if (q != null)
            widget.copy.downloadQuotaLine(
              formatBytes(q.usedBytes),
              formatBytes(q.limitBytes),
            ),
          if (s != null)
            widget.copy.freeStorage(
              formatBytes(s.freeBytes),
              formatBytes(s.totalBytes),
            ),
        ].join('\n'),
        style: TextStyle(color: AppColors.textSecondary),
      ),
    );
  }
}

/// Download speed per item, for the time-left estimate.
final _rates = <String, TransferRate>{};

class _DownloadTile extends ConsumerWidget {
  const _DownloadTile({required this.d, required this.copy});

  final AppDownload d;
  final AppCopy copy;

  String _status() {
    final pct = d.fraction == null ? '' : ' ${(d.fraction! * 100).round()}%';
    final size = d.total == null
        ? formatBytes(d.received)
        : '\u2066${formatBytes(d.received)} / ${formatBytes(d.total!)}\u2069';
    final rate = _rates.putIfAbsent(d.id, TransferRate.new);
    if (d.status == DownloadStatus.downloading) {
      rate.update(d.received, DateTime.now());
    } else {
      rate.reset();
    }
    final left = d.total == null ? null : rate.remaining(d.total! - d.received);
    final eta = left == null ? '' : ' · ${copy.timeLeft(left)}';
    return switch (d.status) {
      DownloadStatus.queued => copy.downloadQueued,
      DownloadStatus.downloading => '${copy.download}$pct · $size$eta',
      DownloadStatus.paused => '${copy.downloadPaused}$pct · $size',
      DownloadStatus.completed => '${copy.downloaded} · $size',
      DownloadStatus.needsPlaybackStop ||
      DownloadStatus.blockedOtherDevice ||
      DownloadStatus.failed =>
        _failureText(copy, d.status, d.message),
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctl = ref.read(appDownloadsProvider.notifier);
    final actions = <Widget>[
      if (d.status == DownloadStatus.completed)
        FilledButton.icon(
          onPressed: () =>
              context.push('/offline/${Uri.encodeComponent(d.id)}'),
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(copy.watchNow),
        ),
      if (d.status == DownloadStatus.downloading ||
          d.status == DownloadStatus.queued)
        OutlinedButton.icon(
          onPressed: () => ctl.pause(d.id),
          icon: const Icon(Icons.pause_rounded),
          label: Text(copy.downloadPause),
        ),
      if (d.status == DownloadStatus.paused)
        FilledButton.icon(
          onPressed: () => ctl.retry(d.id),
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(copy.downloadResume),
        ),
      if (d.status == DownloadStatus.needsPlaybackStop)
        FilledButton.icon(
          onPressed: () => ctl.retry(d.id, stopPlayback: true),
          icon: const Icon(Icons.download_rounded),
          label: Text(copy.downloadStopAndStart),
        ),
      if (d.status == DownloadStatus.failed ||
          d.status == DownloadStatus.blockedOtherDevice)
        FilledButton.icon(
          onPressed: () => ctl.retry(d.id),
          icon: const Icon(Icons.refresh_rounded),
          label: Text(copy.downloadRetry),
        ),
      IconButton(
        tooltip: copy.downloadRemove,
        onPressed: () => ctl.remove(d.id),
        icon: const Icon(Icons.delete_outline_rounded),
      ),
    ];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 60,
              height: 90,
              child: RemoteImage(url: d.posterUrl, memCacheWidth: 180),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  d.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _status(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                if (d.status != DownloadStatus.completed) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      minHeight: 4,
                      value: d.status == DownloadStatus.downloading &&
                              d.fraction == null
                          ? null
                          : (d.fraction ?? 0),
                      backgroundColor: Colors.white12,
                      color: AppColors.cyan,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: actions,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The row text for a stopped download: by status, then storage codes. A
/// server message is shown after "Failed"; the app's own internal messages
/// (English, error type names) are not.
String _failureText(AppCopy copy, DownloadStatus status, String? message) {
  if (status == DownloadStatus.needsPlaybackStop) return copy.downloadNeedsPlaybackStop;
  if (status == DownloadStatus.blockedOtherDevice) return copy.downloadOtherDevicePlaying;
  final m = (message ?? '').trim();
  return switch (m) {
    'DOWNLOAD_LIMIT_REACHED' => copy.downloadLimitReached,
    'DEVICE_FULL' => copy.downloadDeviceFull,
    _ when m.isEmpty || m.startsWith('Download failed') => copy.downloadFailed,
    _ => '${copy.downloadFailed}: $m',
  };
}

/// Client 18 Oct #4: shown while the app runs from the saved session.
class _OfflineBanner extends ConsumerStatefulWidget {
  const _OfflineBanner({required this.copy});

  final AppCopy copy;

  @override
  ConsumerState<_OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends ConsumerState<_OfflineBanner> {
  bool _busy = false;

  Future<void> _retry() async {
    setState(() => _busy = true);
    final ok = await ref.read(sessionProvider.notifier).retryOnline();
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.copy.backOnline)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded, color: Colors.orange, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              ref.watch(deviceInternetProvider).valueOrNull == true
                  ? widget.copy.offlineBannerServer
                  : widget.copy.offlineBanner,
            ),
          ),
          TextButton(
            onPressed: _busy ? null : _retry,
            child: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(widget.copy.retry),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          text,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
      );
}

/// A title this profile downloaded on another device.
class _OtherDeviceTile extends StatelessWidget {
  const _OtherDeviceTile({
    required this.r,
    required this.copy,
    required this.onDownload,
  });

  final ProfileDownloadDto r;
  final AppCopy copy;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final title = cleanDisplayName(r.title ?? '');
    final device = (r.deviceName ?? '').trim();
    final size = r.sizeBytes;
    final sub = [
      if (device.isNotEmpty) copy.downloadedOn(device),
      if (size != null && size > 0) formatBytes(size),
    ].join('  ·  ');
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 54,
              height: 80,
              child: (r.posterUrl ?? '').isEmpty
                  ? const ColoredBox(color: Colors.black26)
                  : Image.network(
                      r.posterUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          const ColoredBox(color: Colors.black26),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.isEmpty ? (r.title ?? '') : title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (sub.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      sub,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: onDownload,
            icon: const Icon(Icons.download_rounded, size: 18),
            label: Text(copy.downloadHere),
          ),
        ],
      ),
    );
  }
}
