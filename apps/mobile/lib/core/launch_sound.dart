import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Survives splash route dispose so the sting isn't cut off mid-play.
AudioPlayer? _launchPlayer;
StreamSubscription<void>? _launchCompleteSub;

void _log(String msg) {
  if (kDebugMode || kProfileMode) debugPrint('[LaunchSound] $msg');
}

/// Plays the APP 4K splash chime. Prefer app-local asset (reliable on
/// Android); fall back to package bytes via temp file / BytesSource.
Future<AudioPlayer?> playAppLaunchSting() async {
  await _disposeLaunchPlayer();

  try {
    await AudioPlayer.global.setAudioContext(
      AudioContext(
        android: const AudioContextAndroid(
          isSpeakerphoneOn: false,
          stayAwake: false,
          contentType: AndroidContentType.music,
          usageType: AndroidUsageType.media,
          audioFocus: AndroidAudioFocus.gainTransientMayDuck,
        ),
      ),
    );
  } catch (e, st) {
    _log('audio context failed: $e\n$st');
  }

  final player = AudioPlayer();
  _launchPlayer = player;
  _launchCompleteSub = player.onPlayerComplete.listen((_) {
    _disposeLaunchPlayer();
  });

  try {
    // mediaPlayer (not lowLatency/SoundPool) — required for MP3 file sources.
    await player.setPlayerMode(PlayerMode.mediaPlayer);
    await player.setReleaseMode(ReleaseMode.stop);
    // Quiet and gentle (client 5 Nov: "far too loud").
    await player.setVolume(0.15);

    final played = await _tryPlayAppAsset(player) ||
        await _tryPlayPackageTempFile(player) ||
        await _tryPlayPackageBytes(player);

    if (!played) {
      _log('all play strategies failed');
      await _disposeLaunchPlayer();
      return null;
    }
    return player;
  } catch (e, st) {
    _log('failed: $e\n$st');
    await _disposeLaunchPlayer();
    return null;
  }
}

Future<bool> _tryPlayAppAsset(AudioPlayer player) async {
  try {
    await player.play(AssetSource('audio/chime.mp3'));
    return true;
  } catch (e) {
    _log('AssetSource failed: $e');
    return false;
  }
}

Future<bool> _tryPlayPackageTempFile(AudioPlayer player) async {
  try {
    final key = AppAssets.packageKey(AppAssets.chime);
    final data = await rootBundle.load(key);
    final bytes = data.buffer.asUint8List();
    final file = File('${Directory.systemTemp.path}/app_launch_chime.mp3');
    await file.writeAsBytes(bytes, flush: true);
    await player.play(DeviceFileSource(file.path, mimeType: 'audio/mpeg'));
    return true;
  } catch (e) {
    _log('temp file play failed: $e');
    return false;
  }
}

Future<bool> _tryPlayPackageBytes(AudioPlayer player) async {
  try {
    final key = AppAssets.packageKey(AppAssets.chime);
    final data = await rootBundle.load(key);
    await player.play(
      BytesSource(data.buffer.asUint8List(), mimeType: 'audio/mpeg'),
    );
    return true;
  } catch (e) {
    _log('BytesSource failed: $e');
    return false;
  }
}

Future<void> _disposeLaunchPlayer() async {
  await _launchCompleteSub?.cancel();
  _launchCompleteSub = null;
  final p = _launchPlayer;
  _launchPlayer = null;
  if (p != null) {
    try {
      await p.stop();
    } catch (_) {}
    try {
      await p.dispose();
    } catch (_) {}
  }
}
