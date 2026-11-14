import 'dart:async';
import 'dart:convert';

import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tv_session.dart';

/// Live programme reminders (client 16 Oct #08): "Remind me" on the next
/// programme from the channel guide; at its start the app shows a banner
/// with Watch. Saved on the backend per profile when the reminders API is
/// there, and on this TV (works offline / with older backends).
///
/// Limit: Android TV has no heads-up notifications for apps, so the alert is
/// shown while the app is open; reminders that start while the app is
/// closed are dropped after 10 minutes.
class TvProgramReminder {
  const TvProgramReminder({
    required this.channelId,
    required this.channelTitle,
    required this.programTitle,
    required this.startsAt,
    this.posterUrl,
  });

  final String channelId;
  final String channelTitle;
  final String programTitle;
  final DateTime startsAt;
  final String? posterUrl;

  String get key => '$channelId@${startsAt.toUtc().toIso8601String()}';

  Map<String, dynamic> toJson() => {
        'channelId': channelId,
        'channelTitle': channelTitle,
        'programTitle': programTitle,
        'startsAt': startsAt.toUtc().toIso8601String(),
        'posterUrl': posterUrl,
      };

  static TvProgramReminder? fromJson(Map<String, dynamic> j) {
    final at = DateTime.tryParse('${j['startsAt'] ?? ''}');
    final id = '${j['channelId'] ?? ''}';
    if (at == null || id.isEmpty) return null;
    return TvProgramReminder(
      channelId: id,
      channelTitle: '${j['channelTitle'] ?? ''}',
      programTitle: '${j['programTitle'] ?? ''}',
      startsAt: at.toLocal(),
      posterUrl: jsonStr(j['posterUrl']),
    );
  }
}

class TvProgramRemindersState {
  const TvProgramRemindersState({this.items = const [], this.due});

  final List<TvProgramReminder> items;

  /// The reminder whose programme is starting now (banner), if any.
  final TvProgramReminder? due;

  bool isSet(String channelId, DateTime startsAt) => items.any(
        (r) =>
            r.channelId == channelId &&
            r.startsAt.isAtSameMomentAs(startsAt),
      );
}

class TvProgramRemindersController
    extends StateNotifier<TvProgramRemindersState> {
  TvProgramRemindersController(this._ref)
      : super(const TvProgramRemindersState()) {
    unawaited(_load());
    _tick = Timer.periodic(const Duration(seconds: 20), (_) => _check());
  }

  final Ref _ref;
  static const _prefsKey = 'app.tv.programReminders.v1';
  static const _late = Duration(minutes: 10);
  Timer? _tick;

  String? get _profileId => _ref.read(tvSessionProvider).activeProfileId;
  ExtrasApi get _api => _ref.read(tvMediaRepositoryProvider).extras;

  Future<void> _load() async {
    final local = <TvProgramReminder>[];
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null) {
        for (final e in jsonDecode(raw) as List) {
          final r = TvProgramReminder.fromJson(
            Map<String, dynamic>.from(e as Map),
          );
          if (r != null) local.add(r);
        }
      }
    } catch (_) {}
    final merged = {for (final r in local) r.key: r};
    final pid = _profileId;
    if (pid != null && pid.isNotEmpty) {
      try {
        final remote = await _api.reminders(pid);
        for (final r in remote ?? const <ReminderDto>[]) {
          final at = r.startsAt;
          if (r.contentType != 'live' || at == null) continue;
          final p = TvProgramReminder(
            channelId: r.streamId,
            channelTitle: r.title ?? '',
            programTitle: r.programTitle ?? '',
            startsAt: at,
            posterUrl: r.posterUrl,
          );
          merged[p.key] = p;
        }
      } catch (_) {}
    }
    if (!mounted) return;
    final now = DateTime.now();
    state = TvProgramRemindersState(
      items: [
        for (final r in merged.values)
          if (r.startsAt.add(_late).isAfter(now)) r,
      ]..sort((a, b) => a.startsAt.compareTo(b.startsAt)),
    );
    _check();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        jsonEncode([for (final r in state.items) r.toJson()]),
      );
    } catch (_) {}
  }

  /// Toggle a reminder for [program] on [channel].
  Future<void> toggle({
    required MediaItem channel,
    required EpgProgramDto program,
  }) async {
    final r = TvProgramReminder(
      channelId: channel.id,
      channelTitle: channel.displayTitle,
      programTitle: program.title,
      startsAt: program.startAt,
      posterUrl: channel.posterUrl,
    );
    final on = state.isSet(channel.id, program.startAt);
    state = TvProgramRemindersState(
      items: on
          ? [for (final e in state.items) if (e.key != r.key) e]
          : ([...state.items, r]
            ..sort((a, b) => a.startsAt.compareTo(b.startsAt))),
      due: state.due,
    );
    unawaited(_save());
    Diag.pb('REMINDER ${on ? 'off' : 'on'} ch=${channel.id} at=${r.startsAt}');
    final pid = _profileId;
    if (pid == null || pid.isEmpty) return;
    try {
      if (on) {
        await _api.removeReminder(
          profileId: pid,
          contentType: 'live',
          streamId: channel.id,
          startsAt: program.startAt,
        );
      } else {
        await _api.addReminder(
          profileId: pid,
          contentType: 'live',
          streamId: channel.id,
          title: channel.displayTitle,
          posterUrl: channel.posterUrl,
          programTitle: program.title,
          startsAt: program.startAt,
        );
      }
    } catch (_) {
      // Kept on this TV; the next sync uploads nothing twice (keyed).
    }
  }

  void _check() {
    if (!mounted || state.due != null) return;
    final now = DateTime.now();
    for (final r in state.items) {
      final startsSoon = !r.startsAt.isAfter(now.add(const Duration(seconds: 30)));
      if (startsSoon && r.startsAt.add(_late).isAfter(now)) {
        Diag.pb('REMINDER due ch=${r.channelId}');
        state = TvProgramRemindersState(
          items: [for (final e in state.items) if (e.key != r.key) e],
          due: r,
        );
        unawaited(_save());
        return;
      }
    }
  }

  /// Banner closed (Watch or Dismiss).
  void clearDue() {
    state = TvProgramRemindersState(items: state.items);
    _check();
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }
}

final tvProgramRemindersProvider = StateNotifierProvider<
    TvProgramRemindersController, TvProgramRemindersState>(
  TvProgramRemindersController.new,
);
