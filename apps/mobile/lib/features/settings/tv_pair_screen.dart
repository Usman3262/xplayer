import 'dart:async';
import 'dart:io';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/session_controller.dart';
import '../../widgets/action_feedback.dart';
import 'tv_device_code_parser.dart';

/// Priority phone: scan TV QR or enter 6-digit code to approve pairing.
class TvPairScreen extends ConsumerStatefulWidget {
  const TvPairScreen({super.key});

  @override
  ConsumerState<TvPairScreen> createState() => _TvPairScreenState();
}

class _TvPairScreenState extends ConsumerState<TvPairScreen> {
  final _code = TextEditingController();

  bool _loading = false;
  bool _scanHandled = false;
  _PairMode _mode = _PairMode.scan;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _approveCode(String raw) async {
    if (_loading) return;
    final copy = AppCopy.ofLanguage(ref.read(sessionProvider).language);
    final code = parseTvDeviceCode(raw);
    if (code == null) {
      await ActionFeedback.error(
        context,
        title: copy.pairTvFailed,
        message: copy.pairTvInvalidCode,
      );
      return;
    }
    setState(() {
      _loading = true;
      _scanHandled = true;
    });
    try {
      await ref.read(sessionProvider.notifier).approveTvDeviceCode(code);
      if (!mounted) return;
      await ActionFeedback.success(
        context,
        title: copy.pairTvSuccess,
        message: copy.pairTvSubtitle,
      );
      if (!mounted) return;
      context.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _scanHandled = false);
      await ActionFeedback.error(
        context,
        title: copy.pairTvFailed,
        message: ActionFeedback.clean(e),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onBarcode(BarcodeCapture capture) {
    if (_scanHandled || _loading || _mode != _PairMode.scan) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.isEmpty) continue;
      if (parseTvDeviceCode(raw) != null) {
        unawaited(_approveCode(raw));
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppCopy.ofLanguage(ref.watch(sessionProvider).language);
    return Scaffold(
      backgroundColor: Colors.black,
      body: AppAtmosphere(
        intensity: 0.85,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => context.pop(),
                      style: IconButton.styleFrom(
                        backgroundColor:
                            AppColors.surface.withValues(alpha: 0.7),
                        side: BorderSide(color: AppColors.border),
                      ),
                      icon: const AppBackIcon(size: 16),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: AppLogo(height: 44, alignToStart: true),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const TechBadge('TV', tone: BadgeTone.magenta),
                const SizedBox(height: 12),
                NeonGlowText(
                  copy.pairTvTitle,
                  color: AppColors.cyan,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 28,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  copy.pairTvSubtitle,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                SegmentedButton<_PairMode>(
                  segments: [
                    ButtonSegment(
                      value: _PairMode.scan,
                      label: Text(copy.pairTvScanTab),
                      icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                    ),
                    ButtonSegment(
                      value: _PairMode.manual,
                      label: Text(copy.pairTvCodeTab),
                      icon: const Icon(Icons.pin_rounded, size: 18),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (set) {
                    setState(() {
                      _mode = set.first;
                      _scanHandled = false;
                    });
                  },
                  style: ButtonStyle(
                    foregroundColor: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.selected)
                          ? Colors.black
                          : AppColors.textSecondary,
                    ),
                    backgroundColor: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.selected)
                          ? AppColors.cyan
                          : AppColors.surface,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: _mode == _PairMode.scan
                      ? _ScanPane(
                          key: const ValueKey('tv-pair-scan'),
                          copy: copy,
                          loading: _loading,
                          onDetect: _onBarcode,
                          onUseCode: () =>
                              setState(() => _mode = _PairMode.manual),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AppTextField(
                              controller: _code,
                              label: copy.pairTvCodeLabel,
                              prefix: Icons.tv_rounded,
                              keyboardType: TextInputType.number,
                              onSubmitted: (_) => _approveCode(_code.text),
                            ),
                            const Spacer(),
                            NeonGlowBorder(
                              child: PrimaryButton(
                                label: copy.pairTvApprove,
                                icon: Icons.verified_user_rounded,
                                loading: _loading,
                                onPressed: _loading
                                    ? null
                                    : () => _approveCode(_code.text),
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _PairMode { scan, manual }

class _ScanPane extends StatefulWidget {
  const _ScanPane({
    super.key,
    required this.copy,
    required this.loading,
    required this.onDetect,
    required this.onUseCode,
  });

  final AppCopy copy;
  final bool loading;
  final void Function(BarcodeCapture capture) onDetect;
  final VoidCallback onUseCode;

  @override
  State<_ScanPane> createState() => _ScanPaneState();
}

class _ScanPaneState extends State<_ScanPane> with WidgetsBindingObserver {
  late final MobileScannerController _controller;
  bool _starting = true;
  bool _permissionDenied = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = MobileScannerController(
      autoStart: false,
      facing: CameraFacing.back,
      detectionSpeed: DetectionSpeed.normal,
      formats: const [BarcodeFormat.qrCode],
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_ensureCamera());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_permissionDenied) return;
    switch (state) {
      case AppLifecycleState.resumed:
        if (!_controller.value.isRunning && !_starting) {
          unawaited(_ensureCamera());
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        if (_controller.value.isRunning) {
          unawaited(_controller.stop());
        }
    }
  }

  Future<void> _ensureCamera() async {
    if (!mounted) return;
    setState(() {
      _starting = true;
      _permissionDenied = false;
      _errorMessage = null;
    });

    final status = await Permission.camera.request();
    if (!mounted) return;
    if (!status.isGranted) {
      setState(() {
        _starting = false;
        _permissionDenied = status.isPermanentlyDenied || status.isDenied;
        _errorMessage = widget.copy.pairTvCameraPermission;
      });
      return;
    }

    try {
      if (_controller.value.isRunning) {
        await _controller.stop();
      }
      await _controller.start();
      if (!mounted) return;
      setState(() {
        _starting = false;
        _errorMessage = null;
      });
    } on MobileScannerException catch (e) {
      if (!mounted) return;
      final denied = e.errorCode == MobileScannerErrorCode.permissionDenied;
      setState(() {
        _starting = false;
        _permissionDenied = denied;
        _errorMessage = denied
            ? widget.copy.pairTvCameraPermission
            : (e.errorDetails?.message ?? e.errorCode.message);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _openSettings() async {
    final opened = await openAppSettings();
    if (!opened && Platform.isIOS) {
      await launchUrl(Uri.parse('app-settings:'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = widget.copy;
    final showError = _errorMessage != null && !_starting;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          copy.pairTvScanHint,
          style: TextStyle(
            color: AppColors.textSecondary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: AppColors.surface),
                if (!showError)
                  MobileScanner(
                    controller: _controller,
                    onDetect: widget.onDetect,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, child) {
                      return _CameraErrorBody(
                        message: error.errorCode ==
                                MobileScannerErrorCode.permissionDenied
                            ? copy.pairTvCameraPermission
                            : (error.errorDetails?.message ??
                                copy.pairTvCameraNeedsRestart),
                        onRetry: () => unawaited(_ensureCamera()),
                        onSettings: _permissionDenied ||
                                error.errorCode ==
                                    MobileScannerErrorCode.permissionDenied
                            ? () => unawaited(_openSettings())
                            : null,
                        onUseCode: widget.onUseCode,
                        copy: copy,
                      );
                    },
                  ),
                if (showError)
                  _CameraErrorBody(
                    message: _errorMessage!,
                    onRetry: () => unawaited(_ensureCamera()),
                    onSettings: _permissionDenied
                        ? () => unawaited(_openSettings())
                        : null,
                    onUseCode: widget.onUseCode,
                    copy: copy,
                  ),
                if (!showError)
                  IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: AppColors.cyan.withValues(alpha: 0.55),
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                if (_starting || widget.loading)
                  Container(
                    color: Colors.black54,
                    alignment: Alignment.center,
                    child: AppLoader.inline(size: 36),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CameraErrorBody extends StatelessWidget {
  const _CameraErrorBody({
    required this.message,
    required this.onRetry,
    required this.onUseCode,
    required this.copy,
    this.onSettings,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onUseCode;
  final VoidCallback? onSettings;
  final AppCopy copy;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.videocam_off_rounded,
              color: AppColors.textSecondary,
              size: 40,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            NeonGlowBorder(
              child: PrimaryButton(
                label: copy.retry,
                icon: Icons.refresh_rounded,
                onPressed: onRetry,
              ),
            ),
            if (onSettings != null) ...[
              const SizedBox(height: 10),
              TextButton(
                onPressed: onSettings,
                child: Text(copy.pairTvOpenSettings),
              ),
            ],
            const SizedBox(height: 8),
            TextButton(
              onPressed: onUseCode,
              child: Text(copy.pairTvCodeTab),
            ),
          ],
        ),
      ),
    );
  }
}
