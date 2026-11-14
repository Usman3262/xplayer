import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_log.dart';

/// Soft UI click. Honors Settings toggle. Uses app-local `assets/audio/unlock.mp3`.
class UiSoundController extends StateNotifier<bool> {
  UiSoundController() : super(true) {
    _load();
  }

  static const _kKey = 'app.ui.sounds';
  final AudioPlayer _player = AudioPlayer();
  bool _ready = false;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_kKey) ?? true;
    try {
      await _player.setPlayerMode(PlayerMode.lowLatency);
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.setVolume(0.55);
    } catch (e) {
      AppLog.error('UiSound', e);
    }
    _ready = true;
    AppLog.info('UiSound', 'ready enabled=$state');
  }

  Future<void> setEnabled(bool enabled) async {
    AppLog.action('ui_sound.set', data: {'enabled': enabled});
    state = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kKey, enabled);
  }

  Future<void> playTap() async {
    if (!_ready || !state) return;
    try {
      await _player.stop();
      await _player.play(AssetSource('audio/unlock.mp3'));
      await HapticFeedback.selectionClick();
    } catch (e) {
      AppLog.error('UiSound', e);
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}

final uiSoundProvider =
    StateNotifierProvider<UiSoundController, bool>((ref) => UiSoundController());

Future<void> playUiTap(WidgetRef ref) {
  AppLog.tap('ui');
  return ref.read(uiSoundProvider.notifier).playTap();
}
