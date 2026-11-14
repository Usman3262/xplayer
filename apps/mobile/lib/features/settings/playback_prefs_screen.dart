import 'package:flutter/foundation.dart';
import 'package:data/data.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/session_controller.dart';
import '../player/player_screen.dart' show kDefaultPlaybackSpeedKey;
import '../../widgets/main_app_bar.dart';

/// Brief §8: Auto / Data saver / Original.
class PlaybackPrefsScreen extends ConsumerStatefulWidget {
  const PlaybackPrefsScreen({super.key});

  @override
  ConsumerState<PlaybackPrefsScreen> createState() => _PlaybackPrefsScreenState();
}

class _PlaybackPrefsScreenState extends ConsumerState<PlaybackPrefsScreen> {
  double _speed = 1.0;

  Future<void> _loadSpeed() async {
    final p = await SharedPreferences.getInstance();
    final v = p.getDouble(kDefaultPlaybackSpeedKey) ?? 1.0;
    if (mounted) setState(() => _speed = v);
  }

  Future<void> _saveSpeed(double v) async {
    setState(() => _speed = v);
    final p = await SharedPreferences.getInstance();
    await p.setDouble(kDefaultPlaybackSpeedKey, v);
  }

  static const qualities = ['Auto', 'Data saver', 'Original'];
  AppDecoderMode _decoderMode = AppDecoderMode.auto;
  bool _nativeEngine = false;
  bool _decoderLoaded = false;
  bool _decoderSaving = false;

  @override
  void initState() {
    super.initState();
    _loadDecoder();
    _loadSpeed();
  }

  Future<void> _loadDecoder() async {
    final mode = await AppDecoderPreferences.load(tv: false);
    final native = await AppDecoderPreferences.nativeEngine(tv: false);
    if (!mounted) return;
    setState(() { _nativeEngine = native; _decoderMode = mode; _decoderLoaded = true; });
  }

  Future<void> _saveDecoder(AppDecoderMode mode) async {
    if (!_decoderLoaded || _decoderSaving) return;
    setState(() => _decoderSaving = true);
    try {
      await AppDecoderPreferences.save(mode, tv: false);
      if (mounted) setState(() => _decoderMode = mode);
    } catch (_) {
      if (mounted) {
        final copy = AppCopy.ofLanguage(ref.read(sessionProvider).language);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(copy.couldNotSaveSetting)),
        );
      }
    } finally {
      if (mounted) setState(() => _decoderSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final copy = AppCopy.ofLanguage(session.language);
    final arabic = session.language == AppLocale.arabic;
    return Scaffold(
      appBar: const MainAppBar(showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            copy.playbackPrefs,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22),
          ),
          const SizedBox(height: 8),
          Text(
            'Auto follows device tier. Data saver prefers lower streams when the API offers variants. Original requests the full file.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 14),
          Text(copy.maxQuality, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final q in qualities)
                ChoiceChip(
                  label: Text(q),
                  selected: session.playbackQuality == q,
                  selectedColor: AppColors.cyan,
                  labelStyle: TextStyle(
                    color: session.playbackQuality == q
                        ? Colors.black
                        : AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                  onSelected: (_) =>
                      ref.read(sessionProvider.notifier).setPlaybackQuality(q),
                ),
            ],
          ),
          const SizedBox(height: 20),
          if (defaultTargetPlatform == TargetPlatform.android)
            SwitchListTile(
              title: Text(arabic ? 'مشغل أندرويد البديل' : 'Android native player'),
              subtitle: Text(arabic ? 'اختبار التوافق. يطبق عند إعادة فتح الفيديو.' : 'Compatibility test. Applies after reopening the video. Basic controls; embedded track selection unavailable.'),
              value: _nativeEngine,
              onChanged: !_decoderLoaded || _decoderSaving ? null : (enabled) async {
                setState(() => _decoderSaving = true);
                try {
                  await AppDecoderPreferences.saveNativeEngine(enabled, tv: false);
                  if (mounted) setState(() => _nativeEngine = enabled);
                } catch (_) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(AppCopy.ofLanguage(
                        ref.read(sessionProvider).language,
                      ).couldNotSaveSetting),
                    ));
                  }
                } finally {
                  if (mounted) setState(() => _decoderSaving = false);
                }
              },
            ),
          Text(arabic ? 'فك ترميز الفيديو' : 'Video decoder',
            style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(arabic
            ? 'أغلق الفيديو وافتحه بعد التغيير. جرب عتاد أندرويد (Surface) عند التقطّع. ارجع إلى التلقائي إذا ظهرت شاشة سوداء أو اختفت الترجمة.'
            : 'Close and reopen the video after changing this setting. Try Android Surface hardware if Auto stutters. If Surface gives a black screen or missing subtitles, return to Auto.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final mode in AppDecoderMode.values)
              if (!mode.androidOnly ||
                  defaultTargetPlatform == TargetPlatform.android)
              ChoiceChip(
                label: Text(mode.label(arabic: arabic)),
                selected: _decoderMode == mode,
                selectedColor: AppColors.cyan,
                onSelected: !_decoderLoaded || _decoderSaving
                  ? null : (_) => _saveDecoder(mode),
              ),
          ]),
          const SizedBox(height: 16),
          Text(copy.playbackSpeed, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final sp in const [0.75, 1.0, 1.25, 1.5, 2.0])
              ChoiceChip(
                label: Text(sp == 1.0 ? copy.speedNormalLabel : '${sp}x'),
                selected: _speed == sp,
                selectedColor: AppColors.cyan,
                onSelected: (_) => _saveSpeed(sp),
              ),
          ]),
          SwitchListTile(
            title: Text(copy.autoplayNextEpisode),
            subtitle: Text(copy.autoplayNextSubtitle),
            value: session.autoplay,
            activeThumbColor: AppColors.cyan,
            onChanged: (v) =>
                ref.read(sessionProvider.notifier).setAutoplay(v),
          ),
        ],
      ),
    );
  }
}
