import 'package:data/data.dart';
import 'package:domain/domain.dart' show AppBrand;
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Short reason shown under the error message, e.g.
/// `OPEN_FAILED kind=connectionLimit http=456`. Null when nothing recorded.
String? tvPlaybackErrorCode() {
  final line = DiagTrail.lastContaining('ERROR code=') ??
      DiagTrail.lastContaining('PLAYBACK_FAILED');
  if (line == null) return null;
  final code = line.replaceFirst('ERROR code=', '');
  final cut = code.indexOf(' videoController=');
  return cut > 0 ? code.substring(0, cut) : code;
}

String? _appVersion;

Future<String> tvAppVersionLabel() async {
  if (_appVersion != null) return _appVersion!;
  try {
    final info = await PackageInfo.fromPlatform();
    _appVersion = '${info.version}+${info.buildNumber}';
  } catch (_) {
    return '?';
  }
  return _appVersion!;
}

String tvDeviceSummary() =>
    DeviceCapabilitiesStore.instance.current?.diagLine ??
    'unknown (capabilities not loaded)';

/// Same report as the mobile app: device/app facts plus the URL-scrubbed
/// [DiagTrail]. No tokens, play URLs or account data.
Future<String> buildTvPlaybackReport({
  required String? userMessage,
  required String contentId,
}) async {
  final version = await tvAppVersionLabel();
  final buf = StringBuffer()
    ..writeln('${AppBrand.name} TV playback report')
    ..writeln('time=${DateTime.now().toIso8601String()} app=$version')
    ..writeln('device ${tvDeviceSummary()}')
    ..writeln('content=$contentId')
    ..writeln('message=${userMessage ?? '-'}')
    ..writeln('code=${tvPlaybackErrorCode() ?? '-'}')
    ..writeln('--- last ${DiagTrail.lines.length} lines ---');
  for (final l in DiagTrail.lines) {
    buf.writeln(l);
  }
  return buf.toString();
}

Future<void> showTvPlaybackDiagnostics(
  BuildContext context, {
  required String? userMessage,
  required String contentId,
}) async {
  final report = await buildTvPlaybackReport(
    userMessage: userMessage,
    contentId: contentId,
  );
  if (!context.mounted) return;
  final scroll = ScrollController();
  final copy = AppCopy.ofContext(context);
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(copy.playbackDetails),
      content: SizedBox(
        width: 900,
        height: MediaQuery.of(ctx).size.height * 0.6,
        child: Scrollbar(
          controller: scroll,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: scroll,
            child: Text(
              report,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
          ),
        ),
      ),
      actions: [
        // Remote: Up/Down on these buttons scroll the report.
        Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: (node, e) {
            if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
              return KeyEventResult.ignored;
            }
            final dy = e.logicalKey == LogicalKeyboardKey.arrowDown
                ? 160.0
                : e.logicalKey == LogicalKeyboardKey.arrowUp
                    ? -160.0
                    : 0.0;
            if (dy == 0 || !scroll.hasClients) return KeyEventResult.ignored;
            scroll.jumpTo((scroll.offset + dy)
                .clamp(0.0, scroll.position.maxScrollExtent));
            return KeyEventResult.handled;
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: report));
                  if (!ctx.mounted) return;
                  ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(
                    SnackBar(content: Text(copy.copiedForSupport)),
                  );
                },
                child: Text(copy.copyText),
              ),
              TextButton(
                autofocus: true,
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(copy.close),
              ),
            ],
          ),
        ),
      ],
    ),
  );
  scroll.dispose();
}
