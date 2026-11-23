import 'dart:async';
import 'dart:io' show Platform;

import 'package:data/data.dart' show RemoteConfig;
import 'package:design_system/design_system.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'remote_config.dart';
import 'session_controller.dart';

const _channelName = 'app/screen_secure';

/// Screen capture protection follows the admin panel (Versions → Player →
/// `player.screen_protection`, default on); users get no switch. It used to
/// come from the old server, which is gone — that left it stuck on.
final screenRecordProtectProvider =
    StateNotifierProvider<ScreenRecordProtectController, bool>((ref) {
  bool fromConfig(RemoteConfig c) => c.boolSetting('player.screen_protection', true);
  final controller = ScreenRecordProtectController(fromConfig(ref.read(remoteConfigProvider)));
  ref.listen<RemoteConfig>(remoteConfigProvider, (_, next) => controller.follow(fromConfig(next)));
  return controller;
});

class ScreenRecordProtectController extends StateNotifier<bool> {
  ScreenRecordProtectController(bool initial) : super(initial) {
    apply(initial);
  }

  /// New value from the server.
  void follow(bool enabled) {
    if (!mounted) return;
    state = enabled;
    apply(enabled);
  }

  static const _channel = MethodChannel(_channelName);

  /// Android: FLAG_SECURE (black / blocked capture). iOS: black overlay while captured.
  Future<void> apply(bool enabled) async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod<void>('setSecure', {'enabled': enabled});
    } catch (e) {
      debugPrint('[ScreenProtect] apply($enabled) failed: $e');
    }
  }

  static Future<bool> isRecording() async {
    if (kIsWeb) return false;
    try {
      final v = await _channel.invokeMethod<bool>('isRecording');
      return v ?? false;
    } catch (_) {
      return false;
    }
  }
}

/// Shows a blocking dialog when capture is detected (iOS); Android relies on FLAG_SECURE.
class ScreenRecordGuard extends ConsumerStatefulWidget {
  const ScreenRecordGuard({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ScreenRecordGuard> createState() => _ScreenRecordGuardState();
}

class _ScreenRecordGuardState extends ConsumerState<ScreenRecordGuard>
    with WidgetsBindingObserver {
  Timer? _poll;
  bool _dialogOpen = false;
  static const _channel = MethodChannel(_channelName);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _channel.setMethodCallHandler(_onNative);
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _check());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final on = ref.read(screenRecordProtectProvider);
      ref.read(screenRecordProtectProvider.notifier).apply(on);
      _check();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _channel.setMethodCallHandler(null);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final on = ref.read(screenRecordProtectProvider);
      ref.read(screenRecordProtectProvider.notifier).apply(on);
      _check();
    }
  }

  Future<void> _onNative(MethodCall call) async {
    if (call.method == 'onRecordingChanged' && call.arguments == true) {
      await _showBlockDialog();
    }
  }

  Future<void> _check() async {
    if (!mounted) return;
    final protect = ref.read(screenRecordProtectProvider);
    if (!protect || kIsWeb) return;
    // Android FLAG_SECURE already blacks recordings; polling isRecording is a no-op.
    if (!kIsWeb && Platform.isAndroid) return;
    final recording = await ScreenRecordProtectController.isRecording();
    if (recording) await _showBlockDialog();
  }

  Future<void> _showBlockDialog() async {
    if (_dialogOpen || !mounted) return;
    _dialogOpen = true;
    final copy = AppCopy.ofLanguage(ref.read(sessionProvider).language);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141414),
        title: Text(copy.screenRecordBlockTitle),
        content: Text(copy.screenRecordBlockMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(copy.confirm),
          ),
        ],
      ),
    );
    if (mounted) _dialogOpen = false;
  }

  @override
  Widget build(BuildContext context) {
    // Touch provider so controller boots with the tree.
    ref.watch(screenRecordProtectProvider);
    return widget.child;
  }
}
