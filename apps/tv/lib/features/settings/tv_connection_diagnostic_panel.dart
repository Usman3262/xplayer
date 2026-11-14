import 'dart:async';

import 'package:data/data.dart' show SpeedTest, SpeedClass, SpeedTestResult;
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tv_locale.dart';
import '../../core/tv_session.dart';
import '../../widgets/focus_tile.dart';
import '../../widgets/tv_remote_scroll_panel.dart';
import '../../widgets/tv_ui.dart';

/// C28: Connection diagnostic on TV (same probes as mobile).
class TvConnectionDiagnosticPanel extends ConsumerStatefulWidget {
  const TvConnectionDiagnosticPanel({super.key});

  @override
  ConsumerState<TvConnectionDiagnosticPanel> createState() =>
      _TvConnectionDiagnosticPanelState();
}

class _TvConnectionDiagnosticPanelState
    extends ConsumerState<TvConnectionDiagnosticPanel> {
  bool _running = false;
  String? _error;
  _DiagResult? _result;
  // Measured download speed (client 20 Oct #10: show "50 / 100 / 300 Mbps").
  SpeedTest? _speedTest;
  double? _liveMbps;
  SpeedTestResult? _speed;
  bool _speedFailed = false;

  Future<void> _run() async {
    if (_running) return;
    setState(() {
      _running = true;
      _error = null;
      _result = null;
      _speed = null;
      _liveMbps = null;
      _speedFailed = false;
    });
    try {
      final api = ref.read(tvAuthRepositoryProvider).client;
      final sw = Stopwatch()..start();
      await api.get('/config/app', auth: false);
      final configMs = sw.elapsedMilliseconds;

      sw.reset();
      sw.start();
      Object? meErr;
      late final int meMs;
      try {
        // Canonical account probe is GET /me (not /auth/me).
        await api.get('/me', auth: true);
        meMs = sw.elapsedMilliseconds;
      } catch (e) {
        meErr = e;
        meMs = sw.elapsedMilliseconds;
      }

      sw.reset();
      sw.start();
      Object? catalogErr;
      late final int catalogMs;
      try {
        await api.get('/catalog/version', auth: true);
        catalogMs = sw.elapsedMilliseconds;
      } catch (e) {
        catalogErr = e;
        catalogMs = sw.elapsedMilliseconds;
      }

      var kbps = 0.0;
      try {
        sw.reset();
        sw.start();
        final raw = await api.get('/config/app', auth: false);
        final bytes = (raw?.toString().length ?? 512).clamp(256, 8192);
        final sec = (sw.elapsedMilliseconds / 1000).clamp(0.05, 30.0);
        kbps = (bytes / 1024) / sec;
      } catch (_) {}

      if (!mounted) return;
      final test = _speedTest = SpeedTest();
      try {
        _speed = await test.run(onProgress: (m) {
          if (mounted) setState(() => _liveMbps = m);
        });
        // Shown to support in the Control Panel (customer details).
        unawaited(ref.read(tvAuthRepositoryProvider).reportSpeed(_speed!.mbps));
      } catch (_) {
        _speedFailed = true;
      }
      if (!mounted) return;
      setState(() {
        _result = _DiagResult(
          configMs: configMs,
          meMs: meMs,
          meError: meErr?.toString(),
          catalogMs: catalogMs,
          catalogError: catalogErr?.toString(),
          approxKbps: kbps,
          at: DateTime.now(),
        );
        _running = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _running = false;
      });
    }
  }

  @override
  void dispose() {
    _speedTest?.cancel();
    super.dispose();
  }

  String _verdict(AppCopy copy, SpeedClass q) => switch (q) {
        SpeedClass.uhd => copy.speedUhd,
        SpeedClass.hd => copy.speedHd,
        SpeedClass.sd => copy.speedSd,
        SpeedClass.poor => copy.speedPoor,
      };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppCopy.ofLanguage(ref.watch(tvLanguageProvider));
    final r = _result;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          copy.support.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          copy.connectionDiagnostic,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22),
        ),
        const SizedBox(height: 8),
        Text(
          copy.connectionDiagnosticHint,
          style: TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 16),
        // Results scroll inside the panel and "Run again" stays in view
        // (client 10 Nov: the results pushed the button off the panel, the
        // remote landed on it out of sight and Up / Down did nothing).
        Expanded(
          child: TvRemoteScrollPanel(
            downLeavesAtEnd: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SpeedReadout(
          title: copy.speedTitle,
          mbps: _speed?.mbps ?? _liveMbps,
          running: _running,
          verdict: _speedFailed
              ? copy.speedFailed
              : _speed == null
                  ? null
                  : _verdict(copy, _speed!.quality),
          verdictColor: _speedFailed || (_speed?.quality == SpeedClass.poor)
              ? AppColors.live
              : AppColors.match,
        ),
        const SizedBox(height: 12),
        if (_error != null)
          Text(_error!, style: TextStyle(color: AppColors.live)),
        if (r != null) ...[
          _row(copy.diagApiConfig, '${r.configMs} ms'),
          _row(
            copy.diagApiAccount,
            r.meError != null
                ? '${r.meMs} ms · ${copy.diagUnavailable}'
                : '${r.meMs} ms',
            error: r.meError != null,
          ),
          _row(
            copy.diagApiCatalog,
            r.catalogError != null
                ? '${r.catalogMs} ms · ${copy.diagUnavailable}'
                : '${r.catalogMs} ms',
            error: r.catalogError != null,
          ),
          _row(
            copy.diagCheckedAt,
            r.at
                .toLocal()
                .toIso8601String()
                .replaceFirst('T', ' ')
                .substring(0, 19),
          ),
        ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FocusTile(
            autofocus: true,
            onTap: _running ? null : () => unawaited(_run()),
            borderRadius: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.cyan.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.cyan),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.speed_rounded, color: AppColors.cyan),
                  const SizedBox(width: 10),
                  Text(
                    copy.diagRunAgain,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _row(String label, String value, {bool error = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: TvUi.meta.copyWith(
                  color: error ? AppColors.live : AppColors.cyan,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiagResult {
  const _DiagResult({
    required this.configMs,
    required this.meMs,
    required this.meError,
    required this.catalogMs,
    required this.catalogError,
    required this.approxKbps,
    required this.at,
  });
  final int configMs;
  final int meMs;
  final String? meError;
  final int catalogMs;
  final String? catalogError;
  final double approxKbps;
  final DateTime at;
}
