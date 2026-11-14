import 'package:data/data.dart';
import 'package:domain/domain.dart' show AppBrand;
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Short reason shown under the error message, e.g.
/// `OPEN_FAILED kind=authorization http=403`. Null when nothing was recorded.
String? playbackErrorCode() {
  final line = DiagTrail.lastContaining('ERROR code=') ??
      DiagTrail.lastContaining('PLAYBACK_FAILED');
  if (line == null) return null;
  final code = line.replaceFirst('ERROR code=', '');
  // Drop the startup timeline that follows the reason.
  final cut = code.indexOf(' videoController=');
  return cut > 0 ? code.substring(0, cut) : code;
}

String? _appVersion;

/// `5.1.17+68`, or `?` when the platform cannot say.
Future<String> appVersionLabel() async {
  if (_appVersion != null) return _appVersion!;
  try {
    final info = await PackageInfo.fromPlatform();
    _appVersion = '${info.version}+${info.buildNumber}';
  } catch (_) {
    return '?';
  }
  return _appVersion!;
}

/// Device summary for reports (model, chip, Android, decoder support).
String deviceSummary() =>
    DeviceCapabilitiesStore.instance.current?.diagLine ??
    'unknown (capabilities not loaded)';

/// Builds the text a user copies and sends to support. Everything in it
/// comes from [DiagTrail] (already URL-scrubbed) plus device and app facts;
/// no tokens, play URLs, or account data.
Future<String> buildPlaybackDiagnosticsReport({
  required String? userMessage,
  required String contentId,
}) async {
  final version = await appVersionLabel();
  final buf = StringBuffer()
    ..writeln('${AppBrand.name} playback report')
    ..writeln('time=${DateTime.now().toIso8601String()} app=$version')
    ..writeln('device ${deviceSummary()}')
    ..writeln('content=$contentId')
    ..writeln('message=${userMessage ?? '-'}')
    ..writeln('code=${playbackErrorCode() ?? '-'}')
    ..writeln('--- last ${DiagTrail.lines.length} lines ---');
  for (final l in DiagTrail.lines) {
    buf.writeln(l);
  }
  return buf.toString();
}

Future<void> showPlaybackDiagnostics(
  BuildContext context, {
  required String? userMessage,
  required String contentId,
}) async {
  final report = await buildPlaybackDiagnosticsReport(
    userMessage: userMessage,
    contentId: contentId,
  );
  if (!context.mounted) return;
  final copy = AppCopy.ofContext(context);
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(copy.playbackDetails),
      content: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.of(ctx).size.height * 0.6,
        child: SingleChildScrollView(
          child: SelectableText(
            report,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
          ),
        ),
      ),
      actions: [
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
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(copy.close),
        ),
      ],
    ),
  );
}
