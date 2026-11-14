import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:domain/domain.dart' show AppBrand;

import 'dart:async';

import 'package:data/data.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/tv_clock.dart';
import '../../core/providers.dart';
import '../../core/tv_catalog_sync.dart' show tvCatalogUpdateProvider;
import '../../core/tv_appearance.dart';
import '../../core/tv_locale.dart';
import '../../core/tv_session.dart';
import '../../widgets/focus_tile.dart';
import '../player/tv_playback_diagnostics.dart';
import 'tv_subscription_screen.dart' show TvSubscriptionCard;
import '../auth/tv_login_screen.dart' show TvHelpDialog;
import '../../widgets/tv_poster.dart';
import '../../widgets/tv_remote_scroll_panel.dart';
import '../../widgets/tv_stream_session_row.dart';
import '../../widgets/tv_ui.dart';
import 'tv_connection_diagnostic_panel.dart';

/// Settings hub nav target (left rail). Content lives in the right panel.
enum _SettingsNav {
  profile,
  subscription,
  devices,
  playback,
  audioSubs,
  autoplay,
  customizeHome,
  appearance,
  language,
  parental,
  library,
  support,
  diagnostic,
  lab,
}

class TvSettingsScreen extends ConsumerStatefulWidget {
  const TvSettingsScreen({super.key});

  @override
  ConsumerState<TvSettingsScreen> createState() => _TvSettingsScreenState();
}

class _TvSettingsScreenState extends ConsumerState<TvSettingsScreen> {
  _SettingsNav _nav = _SettingsNav.profile;
  static const _qualityKey = 'tv_playback_quality';
  static const speedKey = 'tv_playback_speed';
  static const _speeds = ['0.75x', '1.0x', '1.25x', '1.5x', '2.0x'];
  String _speed = '1.0x';
  static const _audioKey = 'tv_audio';
  static const _subsKey = 'tv_subtitles';
  static const _appearanceKey = 'tv_appearance';
  static const _bgIntensityKey = 'tv_bg_intensity';
  static const _accentGlowKey = 'tv_accent_glow';
  static const _motionKey = 'tv_motion';
  static const _cardFocusKey = 'tv_card_focus';
  static const _uiSoundsKey = 'tv_ui_sounds';

  static const _qualities = ['Auto 4K', '1080p', '720p'];
  static const _audios = ['Dolby Atmos · English', 'English stereo', 'Spanish'];
  static const _subs = ['Off', 'English', 'Spanish', 'Closed captions'];
  // C26: three curated theme previews (same set as mobile glass strip).
  static const _appearances = ['Cinematic', 'Midnight', 'Carbon'];
  static const _bgIntensities = ['OLED True Black', 'Deep Dark', 'Soft Dark'];
  static const _accentGlows = ['Off', 'Subtle', 'Vibrant'];
  static const _motions = ['Smooth', 'Standard'];
  static const _cardFocuses = ['Gentle', 'Dynamic'];

  AppDecoderMode _decoderMode = AppDecoderMode.auto;
  bool _nativeEngine = false;
  bool _decoderSaving = false;
  String _quality = _qualities.first;
  String _audio = _audios.first;
  String _subsLabel = _subs.first;
  String _appearance = _appearances.first;
  String _bgIntensity = _bgIntensities.first;
  String _accentGlow = _accentGlows.last;
  String _motion = _motions.first;
  String _cardFocus = _cardFocuses.last;

  /// Kids PIN on the server (set on the phone).
  bool _parentalOn = false;
  bool _uiSounds = true;
  bool _loaded = false;
  String _version = '';

  @override
  void initState() {
    super.initState();
    _load();
    tvAppVersionLabel().then((v) {
      if (mounted) setState(() => _version = v);
    });
    ref.read(tvSessionProvider.notifier).refreshKidsPin().then((on) {
      if (mounted) setState(() => _parentalOn = on);
    });
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final decoderMode = await AppDecoderPreferences.load(tv: true);
    final native = await AppDecoderPreferences.nativeEngine(tv: true);
    if (!mounted) return;
    setState(() {
      _nativeEngine = native;
      _decoderMode = decoderMode;
      _quality = prefs.getString(_qualityKey) ?? _qualities.first;
      _speed = prefs.getString(speedKey) ?? '1.0x';
      _audio = prefs.getString(_audioKey) ?? _audios.first;
      _subsLabel = prefs.getString(_subsKey) ?? _subs.first;
      final savedAppearance =
          prefs.getString(_appearanceKey) ?? _appearances.first;
      _appearance = _appearances.contains(savedAppearance)
          ? savedAppearance
          : _appearances.first;
      _bgIntensity = prefs.getString(_bgIntensityKey) ?? _bgIntensities.first;
      _accentGlow = prefs.getString(_accentGlowKey) ?? _accentGlows.last;
      _motion = prefs.getString(_motionKey) ?? _motions.first;
      _cardFocus = prefs.getString(_cardFocusKey) ?? _cardFocuses.last;
      _uiSounds = prefs.getBool(_uiSoundsKey) ?? true;
      _loaded = true;
    });
  }

  Future<void> _cycleDecoder() async {
    if (!_loaded || _decoderSaving) return;
    final next = AppDecoderMode
        .values[(_decoderMode.index + 1) % AppDecoderMode.values.length];
    setState(() => _decoderSaving = true);
    try {
      await AppDecoderPreferences.save(next, tv: true);
      if (mounted) setState(() => _decoderMode = next);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppCopy.ofLanguage(ref.read(tvLanguageProvider)).couldNotSaveSetting)),
        );
      }
    } finally {
      if (mounted) setState(() => _decoderSaving = false);
    }
  }

  Future<void> _saveString(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  Future<void> _saveBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  String _cycle(List<String> options, String current) {
    final i = options.indexOf(current);
    return options[(i < 0 ? 0 : i + 1) % options.length];
  }

  String _onOff(AppCopy copy, bool on) => on ? copy.enabled : copy.off;

  Future<void> _showAbout(AppCopy copy) async {
    final lang = AppLocale.resolve(ref.read(tvLanguageProvider));
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(copy.about),
        content: Text(
          '${AppBrand.name} ${TvPlatformProfile.pc ? 'for Windows' : 'TV'} $_version\n\n'
          '${copy.mediaPlayerOnlyNotice}\n\n'
          '${AppLegalCopy.copyright(lang)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(copy.confirm),
          ),
        ],
      ),
    );
  }

  Future<void> _showLegal({
    required String title,
    required Widget body,
    required AppCopy copy,
  }) async {
    // Up / Down scroll the text while the close button keeps the focus
    // (client 10 Nov: in Support, Privacy / Terms did not move with the
    // remote; only the button could take the focus).
    final scroll = ScrollController();
    KeyEventResult onKey(FocusNode node, KeyEvent e) {
      if (e is KeyUpEvent || !scroll.hasClients) return KeyEventResult.ignored;
      final down = e.logicalKey == LogicalKeyboardKey.arrowDown;
      if (!down && e.logicalKey != LogicalKeyboardKey.arrowUp) {
        return KeyEventResult.ignored;
      }
      final p = scroll.position;
      scroll.jumpTo(
        (p.pixels + (down ? 120 : -120))
            .clamp(p.minScrollExtent, p.maxScrollExtent)
            .toDouble(),
      );
      return KeyEventResult.handled;
    }

    try {
      await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.background,
        insetPadding: const EdgeInsets.symmetric(horizontal: 48, vertical: 36),
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: onKey,
          child: SizedBox(
          width: 720,
          height: 520,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 20,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: Text(copy.confirm),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: AppColors.border),
              Expanded(
                // The document's list scrolls with this controller.
                child: PrimaryScrollController(
                  controller: scroll,
                  automaticallyInheritForPlatforms:
                      TargetPlatform.values.toSet(),
                  child: body,
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
    } finally {
      scroll.dispose();
    }
  }

  Future<void> _showParentalInfo(AppCopy copy) async {
    final on = await ref.read(tvSessionProvider.notifier).refreshKidsPin();
    if (!mounted) return;
    setState(() => _parentalOn = on);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          '${copy.kidsPinTitle} · ${on ? copy.kidsPinIsOn : copy.off}',
        ),
        content: Text('${copy.kidsPinHint}\n\n${copy.kidsPinOnPhone}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(copy.confirm),
          ),
        ],
      ),
    );
  }

  String _appearanceDesc(AppCopy copy, String name) {
    for (final t in copy.appearanceThemesList) {
      if (t.$1 == name) return t.$2;
    }
    return copy.appliesAcross;
  }

  List<Color> _appearanceSwatches(String name) {
    switch (name) {
      case 'Midnight':
        return const [Color(0xFF0A1628), Color(0xFF4FC3F7), Colors.white];
      case 'Carbon':
        return const [Color(0xFF1A1A1A), Color(0xFFE91E8C), Color(0xFFFF6B9D)];
      case 'Cinematic':
        return [
          Color(0xFF050505),
          AppColors.cyan,
          AppColors.magenta,
        ];
      default:
        return [Color(0xFF0A0A0A), AppColors.textSecondary, Colors.white70];
    }
  }

  /// Real package name for the Subscription row; generic label until loaded.
  String _planLabel(AppCopy copy) {
    final subs = ref.watch(subscriptionsProvider).valueOrNull;
    final name = (subs != null && subs.isNotEmpty)
        ? subs.first.packageName.trim()
        : '';
    return name.isNotEmpty ? name : copy.subscriptionPackage;
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(tvSessionProvider);
    final active = session.activeProfile;
    final profileLabel = active == null
        ? '—'
        : '${active.name}${active.isKids ? ' · ${AppCopy.ofLanguage(ref.watch(tvLanguageProvider)).kids}' : ''}';
    final language = ref.watch(tvLanguageProvider);
    final copy = AppCopy.ofLanguage(language);
    final arabic = language == AppLocale.arabic;
    final langLabel = AppLocale.normalize(language);
    final autoplayOn = session.autoplay;
    final clock = tvClockNow(context);

    final planLabel = _planLabel(copy);

    final navItems = <(_SettingsNav, String, String, IconData, String?)>[
      (
        _SettingsNav.profile,
        copy.manageProfiles,
        profileLabel,
        Icons.person_rounded,
        null,
      ),
      (
        _SettingsNav.subscription,
        copy.subscription,
        planLabel,
        Icons.workspace_premium_outlined,
        null,
      ),
      (
        _SettingsNav.devices,
        copy.devices,
        copy.devicesSessions,
        Icons.tv_rounded,
        null,
      ),
      (
        _SettingsNav.playback,
        copy.playbackPrefs,
        _loaded ? _quality : '…',
        Icons.tune_rounded,
        null,
      ),
      // "Audio & Subtitles" removed (client 20 Oct). Tracks stay
      // switchable in the player (CC / audio buttons).
      (
        _SettingsNav.autoplay,
        copy.autoplay,
        _onOff(copy, autoplayOn),
        Icons.playlist_play_rounded,
        null,
      ),
      (
        _SettingsNav.customizeHome,
        copy.customizeHome,
        copy.configure,
        Icons.view_agenda_outlined,
        TvPlatformProfile.pc ? 'HOME VIEW' : 'TV VIEW',
      ),
      (
        _SettingsNav.appearance,
        copy.appearanceThemes,
        _loaded ? _appearance : '…',
        Icons.palette_outlined,
        _loaded ? 'ACTIVE' : null,
      ),
      (
        _SettingsNav.language,
        copy.language,
        langLabel,
        Icons.bar_chart_rounded,
        null,
      ),
      (
        _SettingsNav.parental,
        copy.parentalControls,
        _parentalOn ? copy.enabled : copy.off,
        Icons.lock_outline_rounded,
        null,
      ),
      (
        _SettingsNav.library,
        copy.libraryHub,
        copy.personalHub,
        Icons.video_library_outlined,
        null,
      ),
      (
        _SettingsNav.support,
        copy.support,
        '${AppBrand.name} ${TvPlatformProfile.pc ? 'for Windows' : 'TV'} $_version',
        Icons.info_outline_rounded,
        null,
      ),
      (
        _SettingsNav.diagnostic,
        copy.connectionDiagnostic,
        copy.connectionDiagnosticHint,
        Icons.speed_rounded,
        null,
      ),
      (
        _SettingsNav.lab,
        copy.sectionLabTesting,
        copy.splashPreview,
        Icons.science_outlined,
        null,
      ),
    ];

    final groups = <(String, List<_SettingsNav>)>[
      (
        copy.sectionAccount,
        [_SettingsNav.profile, _SettingsNav.subscription, _SettingsNav.devices],
      ),
      (copy.sectionPlayback, [_SettingsNav.playback, _SettingsNav.autoplay]),
      (
        copy.sectionPersonalization,
        [_SettingsNav.customizeHome, _SettingsNav.appearance],
      ),
      (
        copy.sectionLookSound,
        [_SettingsNav.language, _SettingsNav.parental, _SettingsNav.library],
      ),
      (copy.support, [_SettingsNav.support, _SettingsNav.diagnostic]),
      // Developer tool: debug builds only (client builds showed it).
      if (kDebugMode) (copy.sectionLabTesting, [_SettingsNav.lab]),
    ];

    final byId = {for (final n in navItems) n.$1: n};

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        TvUi.pageGutter,
        12,
        TvUi.pageGutter,
        16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SettingsHubHeader(
            clock: clock,
            profileName: active?.name ?? AppBrand.name,
            profileLabel: profileLabel,
            onBack: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/home');
              }
            },
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 268,
                  child: TvGlass(
                    radius: 16,
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
                    child: Column(
                      children: [
                        Expanded(
                          child: FocusTraversalGroup(
                            child: ListView(
                              padding: const EdgeInsets.only(bottom: 24),
                              children: [
                                for (final g in groups) ...[
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      8,
                                      10,
                                      8,
                                      6,
                                    ),
                                    child: Text(
                                      g.$1,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 1.1,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ),
                                  for (final id in g.$2)
                                    if (byId[id] != null)
                                      _NavTile(
                                        title: byId[id]!.$2,
                                        subtitle: byId[id]!.$3,
                                        icon: byId[id]!.$4,
                                        badge: byId[id]!.$5,
                                        selected: _nav == id,
                                        onTap: () {
                                          if (id ==
                                              _SettingsNav.customizeHome) {
                                            context.push(
                                              '/settings/customize-home',
                                            );
                                            return;
                                          }
                                          setState(() => _nav = id);
                                        },
                                      ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        FocusTile(
                          borderRadius: 12,
                          borderWidth: 2,
                          onTap: () async {
                            await ref.read(tvSessionProvider.notifier).logout();
                            if (context.mounted) context.go('/login');
                          },
                          child: Container(
                            height: 48,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: AppColors.danger.withValues(
                                alpha: 0.12,
                              ),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppColors.danger.withValues(
                                  alpha: 0.35,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.logout_rounded,
                                  size: 18,
                                  color: AppColors.danger,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        copy.signOutShort,
                                        style: TextStyle(
                                          color: AppColors.danger,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: TvGlass(
                    radius: 16,
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
                    child: _buildPanel(
                      copy: copy,
                      arabic: arabic,
                      active: active,
                      profileLabel: profileLabel,
                      langLabel: langLabel,
                      autoplayOn: autoplayOn,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '${AppBrand.name} ${TvPlatformProfile.pc ? 'for Windows' : 'TV'} $_version',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPanel({
    required AppCopy copy,
    required bool arabic,
    required TvProfile? active,
    required String profileLabel,
    required String langLabel,
    required bool autoplayOn,
  }) {
    switch (_nav) {
      case _SettingsNav.profile:
        return _ProfilePanel(
          copy: copy,
          profileLabel: profileLabel,
          name: active?.name ?? AppBrand.name,
          onManage: () => context.push('/profiles/manage'),
          onSwitch: () {
            // Keep current profile until a new one is chosen so Back works.
            context.push('/profiles');
          },
          onSecurity: () => context.push('/settings/security'),
        );
      // Client 2 Nov: the subscription card itself shows in the panel as
      // soon as Subscription is selected (it used to be one row of text).
      case _SettingsNav.subscription:
        return TvRemoteScrollPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                copy.sectionAccount.toUpperCase(),
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.6,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                copy.subscription,
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 16),
              const TvSubscriptionCard(),
            ],
          ),
        );
      case _SettingsNav.devices:
        return _ActionPanel(
          eyebrow: copy.sectionAccount,
          title: copy.devicesSessions,
          rows: [
            (
              copy.devices,
              copy.devicesBadge,
              () => context.push('/settings/devices'),
            ),
            (
              copy.security,
              copy.devicesSessions,
              () => context.push('/settings/security'),
            ),
            (
              copy.sessionsTitle,
              copy.sessionsSubtitle,
              () => context.push('/settings/security/sessions'),
            ),
          ],
        );
      case _SettingsNav.playback:
        final playbackRows = <(String, String, VoidCallback?)>[
          // Screen capture protection: owner-only in the Control Panel (client 27 Oct).
          (
            copy.playbackPrefs,
            _loaded ? _quality : '…',
            () {
              final next = _cycle(_qualities, _quality);
              setState(() => _quality = next);
              _saveString(_qualityKey, next);
            },
          ),
          // Client 2 Nov: playback speed selectable here (default for every
          // video; the player's own Settings can still change it).
          (
            copy.playbackSpeed,
            _loaded ? _speed : '…',
            () {
              final next = _cycle(_speeds, _speed);
              setState(() => _speed = next);
              _saveString(speedKey, next);
            },
          ),
          if (!TvPlatformProfile.pc) (
            arabic ? 'مشغل أندرويد البديل' : 'Android native player',
            _nativeEngine ? TvPlatformProfile.pc ? 'On' : 'On · recommended for TV' : 'Off · MPV',
            () async {
              if (!_loaded || _decoderSaving) return;
              final next = !_nativeEngine;
              setState(() => _decoderSaving = true);
              try {
                await AppDecoderPreferences.saveNativeEngine(next, tv: true);
                if (mounted) setState(() => _nativeEngine = next);
              } catch (_) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(AppCopy.ofLanguage(ref.read(tvLanguageProvider)).couldNotSaveSetting),
                    ),
                  );
                }
              } finally {
                if (mounted) setState(() => _decoderSaving = false);
              }
            },
          ),
          (
            arabic ? 'فك ترميز الفيديو' : 'Video decoder',
            _loaded
                ? '${TvPlatformProfile.pc ? _decoderMode.pcLabel(arabic: arabic) : _decoderMode.label(arabic: arabic)} · ${arabic ? 'الفيديو التالي' : 'next video'}'
                : '…',
            _cycleDecoder,
          ),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              copy.sectionPlayback.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.0,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              copy.playbackPrefs,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: FocusTraversalGroup(
                child: ListView(
                  clipBehavior: Clip.none,
                  children: [
                    TvStreamSessionRow(copy: copy),
                    const SizedBox(height: 10),
                    for (var i = 0; i < playbackRows.length; i++) ...[
                      if (i > 0) const SizedBox(height: 8),
                      FocusTile(
                        borderRadius: 12,
                        onTap: playbackRows[i].$3,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  playbackRows[i].$1,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                              Text(
                                playbackRows[i].$2,
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      case _SettingsNav.audioSubs:
        return _ActionPanel(
          eyebrow: copy.sectionPlayback,
          title: copy.audioSubtitles,
          rows: [
            (
              copy.audio,
              _loaded ? _audio : '…',
              () {
                final next = _cycle(_audios, _audio);
                setState(() => _audio = next);
                _saveString(_audioKey, next);
              },
            ),
            (
              copy.subtitles,
              _loaded ? _subsLabel : '…',
              () {
                final next = _cycle(_subs, _subsLabel);
                setState(() => _subsLabel = next);
                _saveString(_subsKey, next);
              },
            ),
          ],
        );
      case _SettingsNav.autoplay:
        return _ActionPanel(
          eyebrow: copy.sectionPlayback,
          title: copy.autoplay,
          rows: [
            (
              copy.autoplay,
              _onOff(copy, autoplayOn),
              () =>
                  ref.read(tvSessionProvider.notifier).setAutoplay(!autoplayOn),
            ),
            (
              copy.uiSounds,
              _onOff(copy, _uiSounds),
              () {
                final next = !_uiSounds;
                setState(() => _uiSounds = next);
                _saveBool(_uiSoundsKey, next);
              },
            ),
          ],
        );
      case _SettingsNav.customizeHome:
        return _ActionPanel(
          eyebrow: copy.sectionPersonalization,
          title: copy.customizeHome,
          rows: [
            (
              copy.customizeHome,
              copy.configure,
              () => context.push('/settings/customize-home'),
            ),
          ],
        );
      case _SettingsNav.appearance:
        return _AppearancePanel(
          copy: copy,
          loaded: _loaded,
          selected: _appearance,
          appearances: _appearances,
          descFor: (n) => _appearanceDesc(copy, n),
          swatchesFor: _appearanceSwatches,
          onSelect: (next) {
            setState(() => _appearance = next);
            _saveString(_appearanceKey, next);
            // Apply app-wide theme immediately (P1.13).
            unawaited(
              ref.read(tvAppearanceProvider.notifier).setAppearance(next),
            );
          },
          bgIntensity: _bgIntensity,
          accentGlow: _accentGlow,
          motion: _motion,
          cardFocus: _cardFocus,
          bgOptions: _bgIntensities,
          glowOptions: _accentGlows,
          motionOptions: _motions,
          focusOptions: _cardFocuses,
          onBg: (v) {
            setState(() => _bgIntensity = v);
            _saveString(_bgIntensityKey, v);
          },
          onGlow: (v) {
            setState(() => _accentGlow = v);
            _saveString(_accentGlowKey, v);
          },
          onMotion: (v) {
            setState(() => _motion = v);
            _saveString(_motionKey, v);
          },
          onCardFocus: (v) {
            setState(() => _cardFocus = v);
            _saveString(_cardFocusKey, v);
          },
        );
      case _SettingsNav.language:
        return _ActionPanel(
          eyebrow: copy.sectionLookSound,
          title: copy.language,
          rows: [
            (
              copy.language,
              langLabel,
              () => ref.read(tvLanguageProvider.notifier).toggle(),
            ),
          ],
        );
      case _SettingsNav.parental:
        return _ActionPanel(
          eyebrow: copy.sectionLookSound,
          title: copy.parentalControls,
          rows: [
            (
              copy.parentalControls,
              _parentalOn ? copy.enabled : copy.off,
              () => _showParentalInfo(copy),
            ),
          ],
        );
      case _SettingsNav.library:
        return _ActionPanel(
          eyebrow: copy.libraryHub,
          title: copy.libraryHub,
          rows: [
            (copy.myAccount, copy.personalHub, () => context.go('/my-account')),
            (
              copy.libraryHub,
              copy.libraryHubHint,
              () => context.go('/my-list'),
            ),
            (
              copy.watchLater,
              copy.savedTitles,
              () => context.go('/my-list?tab=watchlater'),
            ),
            (
              copy.downloads,
              copy.downloadsOffline,
              () => context.push('/downloads'),
            ),
            (copy.newAndPopular, copy.trendingComing, () => context.go('/new')),
            (copy.kids, copy.familyTitles, () => context.go('/kids')),
            // Manual refresh of the package's lists (client 5 Nov): the
            // "new content" notice never takes the focus, so the remote
            // reaches the refresh here.
            (
              copy.refreshContent,
              copy.refreshContentHint,
              () {
                ref.read(tvCatalogUpdateProvider.notifier).state = null;
                ref.read(catalogEpochProvider.notifier).state++;
                ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                  SnackBar(content: Text(copy.refreshContentDone)),
                );
              },
            ),
          ],
        );
      case _SettingsNav.support:
        return _ActionPanel(
          eyebrow: copy.support,
          title: copy.about,
          rows: [
            (
              copy.helpSupport,
              copy.helpSubmitRequest,
              () => showDialog<void>(
                context: context,
                builder: (_) => TvHelpDialog(copy: copy),
              ),
            ),
            (copy.about, '${AppBrand.name} ${TvPlatformProfile.pc ? 'for Windows' : 'TV'} $_version', () => _showAbout(copy)),
            (
              copy.privacyPolicy,
              copy.privacySubtitle,
              () => _showLegal(
                title: copy.privacyPolicy,
                body: AppLegalDocumentView.privacy(lang: copy.lang),
                copy: copy,
              ),
            ),
            (
              copy.termsOfUse,
              copy.termsSubtitle,
              () => _showLegal(
                title: copy.termsOfUse,
                body: AppLegalDocumentView.terms(lang: copy.lang),
                copy: copy,
              ),
            ),
          ],
        );
      case _SettingsNav.diagnostic:
        return const TvConnectionDiagnosticPanel();
      case _SettingsNav.lab:
        return _ActionPanel(
          eyebrow: copy.sectionLabTesting,
          title: copy.sectionLabTesting,
          rows: [
            (
              copy.splashPreview,
              copy.splashPreviewHint,
              () => context.push('/settings/lab/splash-preview'),
            ),
          ],
        );
    }
  }
}

class _SettingsHubHeader extends StatelessWidget {
  const _SettingsHubHeader({
    required this.clock,
    required this.profileName,
    required this.profileLabel,
    required this.onBack,
  });

  final String clock;
  final String profileName;
  final String profileLabel;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final initials = profileName.trim().isEmpty
        ? 'C'
        : profileName
              .trim()
              .split(RegExp(r'\s+'))
              .take(2)
              .map((w) => w[0].toUpperCase())
              .join();

    return Row(
      children: [
        FocusTile(
          autofocus: true,
          borderRadius: 12,
          borderWidth: 2,
          onTap: onBack,
          child: Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            ),
            child: const AppBackIcon(
              size: 20,
              style: AppBackIconStyle.material,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'SYSTEM SETTINGS',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.cyan.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'HUB',
                  style: TextStyle(
                    color: AppColors.cyan,
                    fontWeight: FontWeight.w900,
                    fontSize: 9,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        Text(
          clock,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              profileName,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            ),
            Text(
              profileLabel,
              style: const TextStyle(
                color: Color(0xFFE0B35A),
                fontWeight: FontWeight.w700,
                fontSize: 10,
              ),
            ),
          ],
        ),
        const SizedBox(width: 10),
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [
                AppColors.cyan.withValues(alpha: 0.35),
                AppColors.magenta.withValues(alpha: 0.35),
              ],
            ),
            border: Border.all(color: const Color(0xFFE0B35A), width: 1.5),
          ),
          child: Text(
            initials,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String? badge;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) {
        if (!focused) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
          );
        });
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: FocusTile(
          escapeToSidebar: true,
          borderRadius: 12,
          borderWidth: 2,
          onTap: onTap,
          child: Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.cyan.withValues(alpha: 0.12)
                  : Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? AppColors.cyan.withValues(alpha: 0.55)
                    : Colors.white.withValues(alpha: 0.06),
              ),
            ),
            child: Row(
              children: [
                if (selected)
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsetsDirectional.only(end: 8),
                    decoration: BoxDecoration(
                      color: AppColors.cyan,
                      shape: BoxShape.circle,
                    ),
                  )
                else
                  const SizedBox(width: 14),
                Icon(
                  icon,
                  size: 18,
                  color: selected
                      ? AppColors.cyan
                      : AppColors.textSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.2,
                                fontWeight: selected
                                    ? FontWeight.w800
                                    : FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          if (badge != null) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.cyan.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                badge!,
                                style: TextStyle(
                                  color: AppColors.cyan,
                                  fontSize: 8,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 10,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionPanel extends StatelessWidget {
  const _ActionPanel({
    required this.eyebrow,
    required this.title,
    required this.rows,
  });

  final String eyebrow;
  final String title;
  final List<(String, String, VoidCallback?)> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          eyebrow.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: FocusTraversalGroup(
            child: ListView.separated(
              clipBehavior: Clip.none,
              itemCount: rows.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final row = rows[i];
                return FocusTile(
                  borderRadius: 12,
                  borderWidth: 2,
                  // Down on the last option stays in the section (client
                  // 9 Nov: it jumped into the left menu).
                  onKeyFirst: i == rows.length - 1
                      ? (e) => e is! KeyUpEvent &&
                              e.logicalKey == LogicalKeyboardKey.arrowDown
                          ? KeyEventResult.handled
                          : KeyEventResult.ignored
                      : null,
                  onTap: row.$3,
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 56),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                row.$1,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                              ),
                              if (row.$2.isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Text(
                                  row.$2,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: AppColors.textSecondary,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _ProfilePanel extends StatelessWidget {
  const _ProfilePanel({
    required this.copy,
    required this.profileLabel,
    required this.name,
    required this.onManage,
    required this.onSwitch,
    required this.onSecurity,
  });

  final AppCopy copy;
  final String profileLabel;
  final String name;
  final VoidCallback onManage;
  final VoidCallback onSwitch;
  final VoidCallback onSecurity;

  @override
  Widget build(BuildContext context) {
    final initials = name.trim().isEmpty
        ? 'C'
        : name
              .trim()
              .split(RegExp(r'\s+'))
              .take(2)
              .map((w) => w[0].toUpperCase())
              .join();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    copy.sectionAccount.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        'Profile & Identity',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 22,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.cyan.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          copy.primaryBadge,
                          style: TextStyle(
                            color: AppColors.cyan,
                            fontWeight: FontWeight.w900,
                            fontSize: 9,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            TvButton(
              label: copy.editProfileDetails,
              icon: Icons.edit_outlined,
              onTap: onManage,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: ListView(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                child: Row(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFFE0B35A),
                              width: 2,
                            ),
                            gradient: LinearGradient(
                              colors: [
                                AppColors.cyan.withValues(alpha: 0.25),
                                AppColors.magenta.withValues(alpha: 0.25),
                              ],
                            ),
                          ),
                          child: Text(
                            initials,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 22,
                            ),
                          ),
                        ),
                        Positioned(
                          left: 8,
                          right: 8,
                          bottom: -4,
                          child: Container(
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE0B35A),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'VIP',
                              style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.w900,
                                fontSize: 8,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 18,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const TvPill(
                                '● Verified',
                                tone: TvPillTone.success,
                                compact: true,
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            profileLabel,
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _InfoCard(
                      title: copy.security,
                      body: copy.devicesSessions,
                      onTap: onSecurity,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _InfoCard(
                      title: copy.switchProfileManage,
                      body: profileLabel,
                      onTap: onSwitch,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.title,
    required this.body,
    required this.onTap,
  });

  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FocusTile(
      borderRadius: 12,
      // The last row of the section: Down stays here (client 9 Nov).
      onKeyFirst: (e) => e is! KeyUpEvent &&
              e.logicalKey == LogicalKeyboardKey.arrowDown
          ? KeyEventResult.handled
          : KeyEventResult.ignored,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              body,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppearancePanel extends StatelessWidget {
  const _AppearancePanel({
    required this.copy,
    required this.loaded,
    required this.selected,
    required this.appearances,
    required this.descFor,
    required this.swatchesFor,
    required this.onSelect,
    required this.bgIntensity,
    required this.accentGlow,
    required this.motion,
    required this.cardFocus,
    required this.bgOptions,
    required this.glowOptions,
    required this.motionOptions,
    required this.focusOptions,
    required this.onBg,
    required this.onGlow,
    required this.onMotion,
    required this.onCardFocus,
  });

  final AppCopy copy;
  final bool loaded;
  final String selected;
  final List<String> appearances;
  final String Function(String) descFor;
  final List<Color> Function(String) swatchesFor;
  final ValueChanged<String> onSelect;
  final String bgIntensity;
  final String accentGlow;
  final String motion;
  final String cardFocus;
  final List<String> bgOptions;
  final List<String> glowOptions;
  final List<String> motionOptions;
  final List<String> focusOptions;
  final ValueChanged<String> onBg;
  final ValueChanged<String> onGlow;
  final ValueChanged<String> onMotion;
  final ValueChanged<String> onCardFocus;

  Widget _settingBlock(
    String title, {
    String? subtitle,
    required Widget control,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
          ),
          if ((subtitle ?? '').isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: TextStyle(
                color: AppColors.cyan.withValues(alpha: 0.85),
                fontWeight: FontWeight.w700,
                fontSize: 10,
              ),
            ),
          ],
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: control,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          copy.sectionPersonalization.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          copy.appearanceThemes,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 3,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Curated Themes',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 8),
                          TvPill(
                            '${appearances.length} AVAILABLE',
                            tone: TvPillTone.muted,
                            compact: true,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      FocusTraversalGroup(
                        child: GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                mainAxisSpacing: 10,
                                crossAxisSpacing: 10,
                                childAspectRatio: 1.55,
                              ),
                          itemCount: appearances.length,
                          itemBuilder: (_, i) {
                            final name = appearances[i];
                            final on = loaded && name == selected;
                            final swatches = swatchesFor(name);
                            final a = swatches.isNotEmpty
                                ? swatches[0]
                                : AppColors.cyan;
                            final b = swatches.length > 1
                                ? swatches[1]
                                : AppColors.magenta;
                            final c = swatches.length > 2
                                ? swatches[2]
                                : Colors.black;
                            return FocusTile(
                              autofocus: i == 0,
                              borderRadius: 14,
                              borderWidth: 2.5,
                              onTap: loaded ? () => onSelect(name) : null,
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      a.withValues(alpha: 0.35),
                                      c.withValues(alpha: 0.9),
                                      b.withValues(alpha: 0.28),
                                    ],
                                  ),
                                  border: Border.all(
                                    color: on
                                        ? a.withValues(alpha: 0.9)
                                        : Colors.white.withValues(alpha: 0.12),
                                    width: on ? 2 : 1,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                        if (on)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppColors.cyan,
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              copy.profileActive.toUpperCase(),
                                              style: const TextStyle(
                                                color: Colors.black,
                                                fontSize: 8,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Expanded(
                                      child: Text(
                                        descFor(name),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 10,
                                          height: 1.3,
                                        ),
                                      ),
                                    ),
                                    Row(
                                      children: [
                                        for (final sw in swatches)
                                          Container(
                                            width: 12,
                                            height: 12,
                                            margin:
                                                const EdgeInsetsDirectional.only(
                                                  end: 4,
                                                ),
                                            decoration: BoxDecoration(
                                              color: sw,
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: Colors.white24,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              copy.displaySettings,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _settingBlock(
                              copy.backgroundIntensity,
                              control: TvSegmentedControl(
                                options: bgOptions,
                                selected: bgIntensity,
                                onSelect: onBg,
                              ),
                            ),
                            _settingBlock(
                              copy.accentGlow,
                              control: TvSegmentedControl(
                                options: glowOptions,
                                selected: accentGlow,
                                onSelect: onGlow,
                              ),
                            ),
                            _settingBlock(
                              copy.motionLabel,
                              subtitle: copy.smoothTransitionsHint,
                              control: TvSegmentedControl(
                                options: motionOptions,
                                selected: motion,
                                onSelect: onMotion,
                              ),
                            ),
                            _settingBlock(
                              copy.cardFocusAnimation,
                              subtitle: cardFocus,
                              control: TvSegmentedControl(
                                options: focusOptions,
                                selected: cardFocus,
                                onSelect: onCardFocus,
                                stopDown: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              color: Color(0xFF22C55E),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'LIVE PREVIEW',
                            style: TextStyle(
                              color: AppColors.cyan.withValues(alpha: 0.95),
                              fontWeight: FontWeight.w900,
                              fontSize: 10,
                              letterSpacing: 1.0,
                            ),
                          ),
                          const Spacer(),
                          TvPill(
                            bgIntensity,
                            tone: TvPillTone.muted,
                            compact: true,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                const Color(0xFF101820),
                                swatchesFor(selected).first,
                              ],
                            ),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          padding: const EdgeInsets.all(12),
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Row(
                                  children: [
                                    AppLogo(height: 20, alignToStart: true),
                                    Spacer(),
                                    TvPill(
                                      'PREVIEW',
                                      tone: TvPillTone.cyan,
                                      compact: true,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                const TvPill(
                                  'WORLD PREMIERE',
                                  tone: TvPillTone.magenta,
                                  compact: true,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  selected,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '4K ULTRA HD · DOLBY ATMOS · Glow $accentGlow',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 10,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  height: 26,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: AppColors.cyan,
                                    borderRadius: BorderRadius.circular(8),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.cyan.withValues(
                                          alpha: 0.35,
                                        ),
                                        blurRadius: 10,
                                      ),
                                    ],
                                  ),
                                  child: Text(
                                    copy.watchNow,
                                    style: const TextStyle(
                                      color: Colors.black,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const SizedBox(
                                  height: 64,
                                  child: TvPreviewRailSkeleton(
                                    title: 'TRENDING IN DOLBY VISION',
                                    count: 3,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                TvStatusFooter(
                                  left:
                                      'Preset: $selected · $motion · $cardFocus',
                                  right: 'Real-Time Display Preview',
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
