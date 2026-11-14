import 'package:design_system/design_system.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/demo_mode.dart';
import '../core/downloads_controller.dart';

/// Download control for one movie or episode (client 18 Oct #12): a
/// download arrow, a progress ring while it downloads, and a phone with a
/// check mark once the file is on this phone (tap plays it offline).
class DownloadStatusButton extends ConsumerWidget {
  const DownloadStatusButton({super.key, required this.item, this.size = 40});

  final MediaItem item;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = AppCopy.ofContext(context);
    final demo = ref.watch(demoModeProvider);
    AppDownload? dl;
    // Demo: no account, no downloads (the controller is never started).
    for (final e in demo ? const <AppDownload>[] : ref.watch(appDownloadsProvider)) {
      if (e.id == item.id) {
        dl = e;
        break;
      }
    }
    final status = dl?.status;
    final Widget icon;
    final String tip;
    switch (status) {
      case null:
        icon = Icon(Icons.download_rounded, color: AppColors.cyan);
        tip = copy.download;
      case DownloadStatus.completed:
        icon = Icon(
          Icons.mobile_friendly_rounded,
          color: AppColors.cyan,
        );
        tip = copy.downloaded;
      case DownloadStatus.downloading:
      case DownloadStatus.queued:
        final f = dl!.fraction;
        icon = SizedBox(
          width: size * 0.62,
          height: size * 0.62,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CircularProgressIndicator(
                value: status == DownloadStatus.queued ? null : f,
                strokeWidth: 2.6,
                color: AppColors.cyan,
                backgroundColor: Colors.white24,
              ),
              Center(
                child: Icon(
                  Icons.stop_rounded,
                  size: size * 0.32,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        );
        tip = status == DownloadStatus.queued
            ? copy.downloadQueued
            : '${copy.download} ${((f ?? 0) * 100).round()}%';
      case DownloadStatus.paused:
        icon = Icon(
          Icons.pause_circle_outline_rounded,
          color: AppColors.gold,
        );
        tip = copy.downloadPaused;
      default:
        icon = Icon(
          Icons.error_outline_rounded,
          color: AppColors.magenta,
        );
        tip = copy.downloadFailed;
    }
    return Tooltip(
      message: tip,
      child: InkResponse(
        radius: size * 0.6,
        onTap: () {
          final d = dl;
          if (demo) {
            context.push(demoSignInRoute);
          } else if (d == null) {
            ref.read(appDownloadsProvider.notifier).enqueue(item);
          } else if (d.status == DownloadStatus.completed) {
            context.push('/offline/${Uri.encodeComponent(item.id)}');
          } else {
            context.push('/downloads');
          }
        },
        child: SizedBox(
          width: size,
          height: size,
          child: Center(child: icon),
        ),
      ),
    );
  }
}
