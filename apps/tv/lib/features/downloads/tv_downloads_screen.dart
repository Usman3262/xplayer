import 'dart:async';

import 'package:data/data.dart'
    show DeviceStorage, DownloadQuotaDto, ExtrasApi, ProfileDownloadDto;
import 'package:design_system/design_system.dart';
import 'package:domain/domain.dart'
    show TransferRate, cleanDisplayName, formatBytes;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart' show deviceInternetProvider;
import '../../core/tv_session.dart';
import '../../core/tv_downloads.dart';
import '../../core/tv_locale.dart';
import '../../widgets/tv_page_header.dart';
import '../../widgets/tv_ui.dart';

/// Offline downloads (client 16 Oct #20): queue, progress, pause / resume /
/// retry / remove, and offline playback of completed files.
class TvDownloadsScreen extends ConsumerWidget {
  const TvDownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = AppCopy.ofLanguage(ref.watch(tvLanguageProvider));
    final items = ref.watch(tvDownloadsProvider);
    final offline = ref.watch(tvSessionProvider.select((s) => s.offline));
    // Pushed outside the shell: needs its own Material for text styles.
    return Scaffold(
      backgroundColor: Colors.black,
      body: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TvPageHeader(
              title: copy.downloads,
              titleAlt: 'التنزيلات',
              countLabel: items.isEmpty ? null : '${items.length}',
              showSearch: false,
            ),
            if (offline)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.wifi_off_rounded, color: Colors.orange),
                    const SizedBox(width: 10),
                    Text(
                      ref.watch(deviceInternetProvider).valueOrNull == true
                          ? copy.offlineBannerServer
                          : copy.offlineBanner,
                      style: const TextStyle(fontSize: 18),
                    ),
                  ],
                ),
              ),
            _TvStorageLine(
                          copy: copy,
                          extras: ref.read(tvMediaRepositoryProvider).extras,
                          reconcile: ref.read(tvDownloadsProvider.notifier).reconcileWithServer,
                        ),
            Expanded(
              // The profile's downloads on its other devices (client 12 Nov
              // #6/#7, Usman 13 Nov), under this TV's, with "Download here".
              child: ValueListenableBuilder<List<ProfileDownloadDto>>(
                valueListenable:
                    ref.read(tvDownloadsProvider.notifier).profileDownloads,
                builder: (context, _, _) {
                  final ctl = ref.read(tvDownloadsProvider.notifier);
                  final others = offline
                      ? const <ProfileDownloadDto>[]
                      : ctl.otherDevices();
                  if (items.isEmpty && others.isEmpty) {
                    return Center(
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 560),
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: const Color(0xFF111622),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                        ),
                        child: AppEmpty(
                          title: copy.downloadsEmpty,
                          subtitle: copy.downloadsEmptyHint,
                          icon: Icons.download_rounded,
                        ),
                      ),
                    );
                  }
                  final rows = <Widget>[
                    if (others.isNotEmpty && items.isNotEmpty)
                      _TvSectionTitle(copy.downloadsOnThisDevice),
                    for (var i = 0; i < items.length; i++)
                      _DownloadRow(d: items[i], copy: copy, first: i == 0),
                    if (others.isNotEmpty) ...[
                      _TvSectionTitle(copy.downloadsOnOtherDevices),
                      for (var i = 0; i < others.length; i++)
                        _OtherDeviceRow(
                          r: others[i],
                          copy: copy,
                          first: items.isEmpty && i == 0,
                          onDownload: () =>
                              ctl.enqueueFromOtherDevice(others[i]),
                        ),
                    ],
                  ];
                  return ListView.separated(
                    padding: const EdgeInsets.only(top: 16),
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => rows[i],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Free space on the TV, refreshed every 10 s while the screen is open.
class _TvStorageLine extends StatefulWidget {
  const _TvStorageLine({required this.copy, required this.extras, this.reconcile});

  final AppCopy copy;
  final ExtrasApi extras;
  final Future<void> Function()? reconcile;

  @override
  State<_TvStorageLine> createState() => _TvStorageLineState();
}

class _TvStorageLineState extends State<_TvStorageLine> {
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
      padding: const EdgeInsets.only(top: 8),
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
        style: TextStyle(color: AppColors.textSecondary, fontSize: 15),
      ),
    );
  }
}

/// Download speed per item, for the time-left estimate.
final _rates = <String, TransferRate>{};

class _DownloadRow extends ConsumerWidget {
  const _DownloadRow({
    required this.d,
    required this.copy,
    required this.first,
  });

  final TvDownload d;
  final AppCopy copy;
  final bool first;

  String _status() {
    final pct = d.fraction == null ? '' : ' ${(d.fraction! * 100).round()}%';
    final mb = d.total == null
        ? formatBytes(d.received)
        : '\u2066${formatBytes(d.received)} / ${formatBytes(d.total!)}\u2069';
    final rate = _rates.putIfAbsent(d.id, TransferRate.new);
    if (d.status == TvDownloadStatus.downloading) {
      rate.update(d.received, DateTime.now());
    } else {
      rate.reset();
    }
    final left = d.total == null ? null : rate.remaining(d.total! - d.received);
    final eta = left == null ? '' : ' · ${copy.timeLeft(left)}';
    return switch (d.status) {
      TvDownloadStatus.queued => copy.downloadQueued,
      TvDownloadStatus.downloading => '${copy.download}$pct · $mb$eta',
      TvDownloadStatus.paused => '${copy.downloadPaused}$pct · $mb',
      TvDownloadStatus.completed => '${copy.downloaded} · $mb',
      TvDownloadStatus.needsPlaybackStop ||
      TvDownloadStatus.blockedOtherDevice ||
      TvDownloadStatus.failed => _failureText(copy, d.status, d.message),
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctl = ref.read(tvDownloadsProvider.notifier);
    final buttons = <Widget>[
      if (d.status == TvDownloadStatus.completed)
        TvButton(
          primary: true,
          autofocus: first,
          icon: Icons.play_arrow_rounded,
          label: copy.watchNow,
          onTap: () => context.push('/offline/${Uri.encodeComponent(d.id)}'),
        ),
      if (d.status == TvDownloadStatus.downloading ||
          d.status == TvDownloadStatus.queued)
        TvButton(
          autofocus: first,
          icon: Icons.pause_rounded,
          label: copy.downloadPause,
          onTap: () => ctl.pause(d.id),
        ),
      if (d.status == TvDownloadStatus.paused)
        TvButton(
          primary: true,
          autofocus: first,
          icon: Icons.play_arrow_rounded,
          label: copy.downloadResume,
          onTap: () => ctl.retry(d.id),
        ),
      if (d.status == TvDownloadStatus.needsPlaybackStop)
        TvButton(
          primary: true,
          autofocus: first,
          icon: Icons.download_rounded,
          label: copy.downloadStopAndStart,
          onTap: () => ctl.retry(d.id, stopPlayback: true),
        ),
      if (d.status == TvDownloadStatus.failed ||
          d.status == TvDownloadStatus.blockedOtherDevice)
        TvButton(
          primary: true,
          autofocus: first,
          icon: Icons.refresh_rounded,
          label: copy.downloadRetry,
          onTap: () => ctl.retry(d.id),
        ),
      TvButton(
        icon: Icons.delete_outline_rounded,
        label: copy.downloadRemove,
        onTap: () => ctl.remove(d.id),
      ),
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111622),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 64,
              height: 96,
              child: d.posterUrl == null
                  ? const ColoredBox(color: Color(0xFF1B2232))
                  : Image.network(
                      d.posterUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          const ColoredBox(color: Color(0xFF1B2232)),
                    ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  d.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _status(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                if (d.status != TvDownloadStatus.completed)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      minHeight: 5,
                      value:
                          d.status == TvDownloadStatus.downloading &&
                              d.fraction == null
                          ? null
                          : (d.fraction ?? 0),
                      backgroundColor: Colors.white.withValues(alpha: 0.12),
                      color: const Color(0xFF22D3EE),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Wrap(spacing: TvUi.buttonGap, children: buttons),
        ],
      ),
    );
  }
}

/// The row text for a stopped download: by status, then storage codes. A
/// server message is shown after "Failed"; the app's own internal messages
/// (English, error type names) are not.
String _failureText(AppCopy copy, TvDownloadStatus status, String? message) {
  if (status == TvDownloadStatus.needsPlaybackStop) return copy.downloadNeedsPlaybackStop;
  if (status == TvDownloadStatus.blockedOtherDevice) return copy.downloadOtherDevicePlaying;
  final m = (message ?? '').trim();
  return switch (m) {
    'DOWNLOAD_LIMIT_REACHED' => copy.downloadLimitReached,
    'DEVICE_FULL' => copy.downloadDeviceFull,
    _ when m.isEmpty || m.startsWith('Download failed') => copy.downloadFailed,
    _ => '${copy.downloadFailed}: $m',
  };
}

class _TvSectionTitle extends StatelessWidget {
  const _TvSectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
}

/// A title this profile downloaded on another device, with "Download here".
class _OtherDeviceRow extends StatelessWidget {
  const _OtherDeviceRow({
    required this.r,
    required this.copy,
    required this.first,
    required this.onDownload,
  });

  final ProfileDownloadDto r;
  final AppCopy copy;
  final bool first;
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111622),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 64,
              height: 96,
              child: (r.posterUrl ?? '').isEmpty
                  ? const ColoredBox(color: Color(0xFF1B2232))
                  : Image.network(
                      r.posterUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          const ColoredBox(color: Color(0xFF1B2232)),
                    ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.isEmpty ? (r.title ?? '') : title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (sub.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      sub,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 15,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          TvButton(
            primary: true,
            autofocus: first,
            icon: Icons.download_rounded,
            label: copy.downloadHere,
            onTap: onDownload,
          ),
        ],
      ),
    );
  }
}
