import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'session_controller.dart';

/// Offline downloads on the backend grant API (same engine as the TV app).
///
/// - One provider download at a time (queue); online playback pauses it
///   first ([PlaybackArbiter]) because the line allows one connection.
/// - Files live in app-private storage (`getApplicationSupportDirectory`).
/// - Persisted per entry: id, title, poster, status, bytes, grant id, file
///   name. Never the download URL (it carries the line credentials): after a
///   restart an interrupted entry shows Paused; Resume re-authorizes and
///   continues the partial file with HTTP Range.
/// - Runs while the app is in the foreground. Android and iOS suspend the
///   app soon after it is backgrounded, so a transfer stops then; it shows
///   Paused on return and Resume continues from the partial file. There is
///   no background download service / URLSession yet (documented limit).
enum DownloadStatus {
  queued,
  downloading,
  paused,
  needsPlaybackStop,
  blockedOtherDevice,
  failed,
  completed,
}

class AppDownload {
  const AppDownload({
    required this.id,
    required this.title,
    required this.contentType,
    required this.status,
    this.posterUrl,
    this.container,
    this.seriesId,
    this.grantId,
    this.fileName,
    this.received = 0,
    this.total,
    this.message,
    this.restartedFromZero = false,
  });

  final String id;
  final String title;
  final String contentType;
  final DownloadStatus status;
  final String? posterUrl;
  final String? container;
  /// Series of an episode (sent on authorize, Usman 13 Nov).
  final String? seriesId;
  final String? grantId;
  final String? fileName;
  final int received;
  final int? total;
  final String? message;
  final bool restartedFromZero;

  double? get fraction =>
      (total == null || total == 0) ? null : (received / total!).clamp(0, 1);

  AppDownload copyWith({
    DownloadStatus? status,
    String? grantId,
    String? fileName,
    int? received,
    int? total,
    String? message,
    bool clearMessage = false,
    bool? restartedFromZero,
  }) =>
      AppDownload(
        id: id,
        title: title,
        contentType: contentType,
        posterUrl: posterUrl,
        container: container,
        seriesId: seriesId,
        status: status ?? this.status,
        grantId: grantId ?? this.grantId,
        fileName: fileName ?? this.fileName,
        received: received ?? this.received,
        total: total ?? this.total,
        message: clearMessage ? null : (message ?? this.message),
        restartedFromZero: restartedFromZero ?? this.restartedFromZero,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'contentType': contentType,
        'status': status.name,
        'posterUrl': posterUrl,
        'container': container,
        'seriesId': seriesId,
        'grantId': grantId,
        'fileName': fileName,
        'received': received,
        'total': total,
        'message': message,
      };

  factory AppDownload.fromJson(Map<String, dynamic> j) => AppDownload(
        id: '${j['id']}',
        title: '${j['title'] ?? ''}',
        contentType: '${j['contentType'] ?? 'vod'}',
        status: DownloadStatus.values.firstWhere(
          (s) => s.name == j['status'],
          orElse: () => DownloadStatus.paused,
        ),
        posterUrl: jsonStr(j['posterUrl']),
        container: jsonStr(j['container']),
        seriesId: jsonStr(j['seriesId']),
        grantId: jsonStr(j['grantId']),
        fileName: jsonStr(j['fileName']),
        received: (jsonDouble(j['received']))?.toInt() ?? 0,
        total: (jsonDouble(j['total']))?.toInt(),
        message: jsonStr(j['message']),
      );
}

class DownloadsController extends StateNotifier<List<AppDownload>> {
  DownloadsController(this._ref) : super(const []) {
    PlaybackArbiter.onBeforePlayback = pauseForPlayback;
    PlaybackArbiter.onAfterPlayback = playbackEnded;
    // Sign-out / another account (client 5 Nov, P17): every download goes.
    _policySub = OfflineDownloadPolicy.events.listen((_) => unawaited(wipeAll()));
    unawaited(_load());
  }

  StreamSubscription<String>? _policySub;

  final Ref _ref;
  static const _prefsKey = 'app.mobile.downloads.v1';
  final _engine = DownloadEngine();
  DownloadCancelToken? _cancel;
  String? _activeId;
  Directory? _dir;
  DateTime _lastServerProgress = DateTime.fromMillisecondsSinceEpoch(0);
  bool _pausedForPlayback = false;

  AppMediaRepository get _media => _ref.read(mediaRepositoryProvider);

  Future<String> _deviceId() =>
      _ref.read(authRepositoryProvider).ensurePlaybackDeviceId();

  Future<Directory> _folder() async {
    final d = _dir ??= Directory(
      '${(await getApplicationSupportDirectory()).path}/downloads',
    );
    await d.create(recursive: true);
    return d;
  }

  Future<File?> fileFor(AppDownload d) async {
    final name = d.fileName;
    if (name == null) return null;
    final f = File('${(await _folder()).path}/$name');
    return await f.exists() ? f : null;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) {
        if (await OfflineDownloadPolicy.wipePending()) await wipeAll();
        return;
      }
      final list = [
        for (final e in jsonDecode(raw) as List)
          AppDownload.fromJson(Map<String, dynamic>.from(e as Map)),
      ];
      // An interrupted transfer (app closed) shows Paused, then continues by
      // itself a few seconds after start (client 20 Oct: a download needed
      // Resume after the app was killed). It waits so a player opened right
      // away keeps the line; a user-paused download stays paused.
      final interrupted = <String>[];
      state = [
        for (final d in list)
          if (d.status == DownloadStatus.downloading ||
              d.status == DownloadStatus.queued) ...[
            () {
              interrupted.add(d.id);
              return d.copyWith(status: DownloadStatus.paused);
            }(),
          ] else
            d,
      ];
      if (interrupted.isNotEmpty) {
        _autoResume.addAll(interrupted);
        _scheduleAutoResume(const Duration(seconds: 6));
      }
    } catch (_) {}
    // Signed out / account changed while this controller was not running.
    if (await OfflineDownloadPolicy.wipePending()) {
      await wipeAll();
      return;
    }
    unawaited(reconcileWithServer());
  }

  /// Deletes every download (files, list, partial files) and tells the server
  /// (best effort: after a sign-out the request may no longer be allowed; the
  /// server drops stale grants by itself). Client 5 Nov, P17.
  Future<void> wipeAll() async {
    _resumeTimer?.cancel();
    _cancel?.cancel();
    _activeId = null;
    _autoResume.clear();
    final old = state;
    state = const [];
    await _save();
    try {
      final d = await _folder();
      if (await d.exists()) await d.delete(recursive: true);
    } catch (_) {}
    _dir = null;
    await OfflineDownloadPolicy.wipeDone();
    for (final e in old) {
      final grant = e.grantId;
      if (grant == null || grant.isEmpty) continue;
      try {
        await _media.downloads.cancel(grant, deviceId: await _deviceId());
      } catch (_) {}
    }
  }

  /// Continues [_autoResume] downloads after [delay] unless playback is on.
  void _scheduleAutoResume(Duration delay) {
    _resumeTimer?.cancel();
    _resumeTimer = Timer(delay, () {
      if (!mounted || _pausedForPlayback) return;
      for (final id in [..._autoResume]) {
        final d = byId(id);
        if (d != null && d.status == DownloadStatus.paused) {
          _put(d.copyWith(status: DownloadStatus.queued, clearMessage: true));
        }
      }
      _autoResume.clear();
      unawaited(_save());
      _pump();
    });
  }

  String? _runningWhenBackgrounded;

  /// App went to the background: remember the running transfer (the OS
  /// may stop it there).
  void appPaused() {
    _runningWhenBackgrounded = _activeId;
  }

  /// App back in the foreground: a transfer that was running when the app
  /// left and is no longer running continues by itself.
  void appResumed() {
    final id = _runningWhenBackgrounded;
    _runningWhenBackgrounded = null;
    if (id == null || _activeId == id) return;
    final d = byId(id);
    if (d == null || d.status == DownloadStatus.completed) return;
    _autoResume.add(id);
    _scheduleAutoResume(const Duration(seconds: 3));
  }

  /// Downloads this device holds -> server; the server stops counting the
  /// rest (deleted files, reinstalls). Runs at start and on the Downloads
  /// screen.
  Future<void> reconcileWithServer() async {
    try {
      await _media.downloads.reconcile(
        deviceId: await _deviceId(),
        keepGrantIds: [
          for (final d in state)
            if (d.grantId != null && d.grantId!.isNotEmpty) d.grantId!,
        ],
      );
    } catch (_) {}
    unawaited(refreshProfileDownloads());
  }

  /// The profile's downloads on every device (Usman 13 Nov), for "On other
  /// devices" on the Downloads screen. A download removed in the panel
  /// (state removed) is deleted here too.
  final profileDownloads = ValueNotifier<List<ProfileDownloadDto>>(const []);
  String? _myDeviceId;

  Future<void> refreshProfileDownloads() async {
    final profileId = _ref.read(sessionProvider).activeProfileId;
    if (profileId == null || profileId.isEmpty) return;
    List<ProfileDownloadDto> list;
    try {
      list = await _media.downloads.forProfile(profileId);
    } catch (_) {
      return;
    }
    _myDeviceId ??= await _deviceId();
    if (!mounted) return;
    profileDownloads.value = list;
    final removed = {
      for (final r in list)
        if (r.isRemoved && r.grantId.isNotEmpty) r.grantId,
    };
    for (final d in [...state]) {
      final g = d.grantId;
      if (g != null && removed.contains(g)) await _dropLocal(d);
    }
  }

  /// Deletes the file and the entry without telling the server (it removed
  /// the grant itself).
  Future<void> _dropLocal(AppDownload d) async {
    if (_activeId == d.id) _cancel?.cancel();
    state = [for (final e in state) if (e.id != d.id) e];
    unawaited(_save());
    try {
      await (await fileFor(d))?.delete();
    } catch (_) {}
  }

  /// Downloads of this profile on the account's other devices that are not
  /// on this one ("Download here").
  List<ProfileDownloadDto> otherDevices() {
    final mine = _myDeviceId;
    if (mine == null) return const [];
    final here = {for (final d in state) d.id};
    final seen = <String>{};
    return [
      for (final r in profileDownloads.value)
        if (!r.isRemoved &&
            r.deviceId != mine &&
            r.playableId.isNotEmpty &&
            !here.contains(r.playableId) &&
            seen.add(r.playableId))
          r,
    ];
  }

  /// "Download here" for a title downloaded on another device, in the same
  /// file format.
  void enqueueFromOtherDevice(ProfileDownloadDto r) {
    final id = r.playableId;
    if (id.isEmpty || byId(id) != null) return;
    final ext = (r.containerExtension ?? '').replaceFirst('.', '');
    state = [
      ...state,
      AppDownload(
        id: id,
        title: cleanDisplayName(r.title ?? '').isEmpty ? (r.title ?? id) : cleanDisplayName(r.title!),
        contentType: r.contentType == 'series' ? 'series' : 'vod',
        status: DownloadStatus.queued,
        posterUrl: r.posterUrl,
        seriesId: r.seriesId,
        container: ext.isEmpty ? null : ext,
        fileName: '$id.${ext.isEmpty ? 'mp4' : ext}',
      ),
    ];
    unawaited(_save());
    _pump();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        jsonEncode([for (final d in state) d.toJson()]),
      );
    } catch (_) {}
  }

  void _put(AppDownload d) {
    state = [for (final e in state) e.id == d.id ? d : e];
    unawaited(_save());
  }

  AppDownload? byId(String id) {
    for (final d in state) {
      if (d.id == id) return d;
    }
    return null;
  }

  /// Adds a movie / episode. Live cannot be downloaded (backend rejects it).
  void enqueue(MediaItem item) {
    if (item.kind == MediaKind.live || item.isLive) return;
    if (byId(item.id) != null) {
      retry(item.id);
      return;
    }
    final type = item.kind == MediaKind.series ? 'series' : 'vod';
    final ext = (item.containerExtension ?? 'mp4').replaceFirst('.', '');
    state = [
      ...state,
      AppDownload(
        id: item.id,
        title: item.displayTitle,
        contentType: type,
        status: DownloadStatus.queued,
        posterUrl: item.posterUrl,
        container: ext,
        seriesId: item.seriesId,
        fileName: '${item.id}.$ext',
      ),
    ];
    unawaited(_save());
    _pump();
  }

  void _pump() {
    if (_activeId != null || _pausedForPlayback) return;
    final next = state.where((d) => d.status == DownloadStatus.queued);
    if (next.isEmpty) return;
    unawaited(_run(next.first.id));
  }

  /// Called before online playback / preview: closes the download socket and
  /// marks it paused (the backend also pauses grants when a lease starts).
  /// Paused for playback; resumed by [playbackEnded].
  final Set<String> _autoResume = {};
  Timer? _resumeTimer;
  final Map<String, int> _busyTries = {};

  Future<String?> pauseForPlayback() async {
    _resumeTimer?.cancel();
    // Another player opened before the resume delay ran out (channel zap,
    // next episode): the queue stays held.
    if (_autoResume.isNotEmpty) _pausedForPlayback = true;
    final id = _activeId;
    if (id == null) return null;
    _pausedForPlayback = true;
    _autoResume.add(id);
    Diag.pb('DOWNLOAD pause for playback id=$id');
    _cancel?.cancel();
    final d = byId(id);
    if (d != null) {
      _put(d.copyWith(
        status: DownloadStatus.paused,
        message: 'Paused for playback',
      ));
    }
    final grant = d?.grantId;
    if (grant != null) {
      try {
        await _media.downloads.pause(grant, deviceId: await _deviceId());
      } catch (_) {}
    }
    return d?.title;
  }

  /// Back from playback: the download paused for it continues by itself
  /// after a short delay (the backend releases the stream lease first; a
  /// new player opening in the meantime cancels the resume).
  void playbackEnded() {
    _resumeTimer?.cancel();
    _resumeTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      _pausedForPlayback = false;
      for (final id in [..._autoResume]) {
        final d = byId(id);
        if (d != null && d.status == DownloadStatus.paused) {
          _put(d.copyWith(status: DownloadStatus.queued, clearMessage: true));
        }
      }
      _autoResume.clear();
      unawaited(_save());
      _pump();
    });
  }

  void pause(String id) {
    _autoResume.remove(id);
    if (_activeId == id) {
      _cancel?.cancel();
    }
    final d = byId(id);
    if (d == null) return;
    _put(d.copyWith(status: DownloadStatus.paused, clearMessage: true));
    final grant = d.grantId;
    if (grant != null) {
      unawaited(() async {
        try {
          await _media.downloads.pause(grant, deviceId: await _deviceId());
        } catch (_) {}
      }());
    }
  }

  /// Resume / retry. [stopPlayback] = the user agreed to stop playback on
  /// this TV (PLAYBACK_ACTIVE_STOP_REQUIRED).
  void retry(String id, {bool stopPlayback = false}) {
    final d = byId(id);
    if (d == null || d.status == DownloadStatus.completed) return;
    _pausedForPlayback = false;
    _put(d.copyWith(status: DownloadStatus.queued, clearMessage: true));
    _stopPlaybackFor = stopPlayback ? id : null;
    _pump();
  }

  String? _stopPlaybackFor;

  Future<void> remove(String id) async {
    final d = byId(id);
    if (d == null) return;
    if (_activeId == id) _cancel?.cancel();
    state = [for (final e in state) if (e.id != id) e];
    unawaited(_save());
    final grant = d.grantId;
    // Completed ones too: the server counts them against the storage
    // limit until told they are gone (17 Oct: "12.5 GB of 10 GB").
    if (grant != null && grant.isNotEmpty) {
      try {
        await _media.downloads.cancel(grant, deviceId: await _deviceId());
      } catch (_) {}
    }
    try {
      await (await fileFor(d))?.delete();
    } catch (_) {}
  }

  /// Stored as the item's message; the Downloads screen shows the text.
  static String _spaceCode(DownloadSpaceProblem p) =>
      p == DownloadSpaceProblem.limitReached
          ? 'DOWNLOAD_LIMIT_REACHED'
          : 'DEVICE_FULL';

  Future<void> _run(String id) async {
    var d = byId(id);
    if (d == null) return;
    _activeId = id;
    final cancel = _cancel = DownloadCancelToken();
    try {
      final deviceId = await _deviceId();
      final url = await _grantUrl(d, deviceId);
      d = byId(id)!;
      if (cancel.isCancelled) return;
      // Storage rules (client 17 Oct): the customer's download limit and a
      // free-space reserve on this device, checked before starting and
      // again once the file size is known.
      final quota = await _media.extras.downloadQuota();
      DownloadSpaceProblem? space = DownloadSpaceGuard.check(
        quota: quota,
        storage: await DeviceStorage.read(),
        remainingBytes: d.total == null ? null : d.total! - d.received,
        ownServerBytes: d.total ?? d.received,
      );
      if (space != null) {
        _put(d.copyWith(status: DownloadStatus.failed, message: _spaceCode(space)));
        Diag.pb('DOWNLOAD blocked id=$id reason=${space.name}');
        return;
      }
      var sizeChecked = d.total != null;
      _put(d.copyWith(status: DownloadStatus.downloading, clearMessage: true));
      Diag.pb('DOWNLOAD start id=$id from=${d.received}');
      final f = File('${(await _folder()).path}/${d.fileName}');
      final stop = await _engine.run(
        url: Uri.parse(url),
        target: f,
        cancel: cancel,
        onRestart: () {
          final cur = byId(id);
          if (cur != null) _put(cur.copyWith(restartedFromZero: true));
        },
        onProgress: (received, total) {
          final cur = byId(id);
          if (cur == null) return;
          if (!sizeChecked && total != null && total > 0) {
            sizeChecked = true;
            unawaited(() async {
              final problem = DownloadSpaceGuard.check(
                quota: quota,
                storage: await DeviceStorage.read(),
                remainingBytes: total - received,
                ownServerBytes: received,
              );
              if (problem != null && !cancel.isCancelled) {
                space = problem;
                cancel.cancel();
              }
            }());
          }
          _put(cur.copyWith(received: received, total: total));
          _reportProgress(cur.grantId, deviceId, received, total);
        },
      );
      final cur = byId(id);
      if (cur == null) return;
      final blocked = space;
      if (blocked != null) {
        _put(cur.copyWith(status: DownloadStatus.failed, message: _spaceCode(blocked)));
        Diag.pb('DOWNLOAD stopped id=$id reason=${blocked.name}');
        final grant = cur.grantId;
        if (grant != null && grant.isNotEmpty) {
          try {
            await _media.downloads.fail(
              grant,
              deviceId: deviceId,
              message: _spaceCode(blocked),
            );
          } catch (_) {}
        }
        return;
      }
      if (stop == DownloadStop.completed) {
        _put(cur.copyWith(status: DownloadStatus.completed, clearMessage: true));
        Diag.pb('DOWNLOAD complete id=$id bytes=${cur.received}');
        try {
          await _media.downloads.complete(cur.grantId!, deviceId: deviceId);
        } catch (_) {}
      }
    } on ApiException catch (e) {
      final cur = byId(id);
      if (cur != null) {
        if (e.code == 'DOWNLOAD_LIMIT_REACHED') {
          _put(cur.copyWith(
            status: DownloadStatus.failed,
            message: 'DOWNLOAD_LIMIT_REACHED',
          ));
        } else if (e.code == 'PLAYBACK_ACTIVE_STOP_REQUIRED') {
          _put(cur.copyWith(
            status: DownloadStatus.needsPlaybackStop,
            message: 'Stop playback on this TV to download?',
          ));
        } else if (e.isPlaybackLeaseHeld) {
          _put(cur.copyWith(
            status: DownloadStatus.blockedOtherDevice,
            message: 'Another device is playing on this account.',
          ));
        } else {
          _put(cur.copyWith(status: DownloadStatus.failed, message: e.message));
        }
      }
    } on DownloadTransferException catch (e) {
      final cur = byId(id);
      if (cur != null && e.lineBusy) {
        // Client 23 Oct #9 ("error 460"): the line's one connection was in
        // use (another device or player). Keep the progress, say why, and
        // try again by itself every 30 s for 20 min.
        final tries = (_busyTries[id] ?? 0) + 1;
        _busyTries[id] = tries;
        _put(cur.copyWith(
          status: tries <= 40 ? DownloadStatus.paused : DownloadStatus.blockedOtherDevice,
          message: 'The account is in use on another device or player. '
              'The download continues by itself when it is free.',
        ));
        if (tries <= 40) {
          _autoResume.add(id);
          _scheduleAutoResume(const Duration(seconds: 30));
        }
      } else if (cur != null) {
        _put(cur.copyWith(
          status: DownloadStatus.failed,
          message: e.message,
          // Expired/refused source: the next retry asks for a new grant.
          grantId: e.needsReauthorize ? '' : null,
        ));
        final grant = cur.grantId;
        if (grant != null && grant.isNotEmpty) {
          try {
            await _media.downloads
                .fail(grant, deviceId: await _deviceId(), message: e.message);
          } catch (_) {}
        }
      }
    } catch (e) {
      final cur = byId(id);
      if (cur != null) {
        _put(cur.copyWith(
          status: DownloadStatus.failed,
          message: 'Download failed (${e.runtimeType})',
        ));
      }
    } finally {
      if (_activeId == id) {
        _activeId = null;
        _cancel = null;
      }
      _pump();
    }
  }

  /// URL for this entry: resume the stored grant, or authorize a new one
  /// (first start, expired / refused grant). URL kept in memory only.
  Future<String> _grantUrl(AppDownload d, String deviceId) async {
    final api = _media.downloads;
    final grant = d.grantId;
    if (grant != null && grant.isNotEmpty) {
      try {
        // Resume returns a fresh URL (backend 16 Oct: list/get no longer
        // carry it). A grant that is still ACTIVE on the server (app was
        // killed) is not resumable: a new grant is authorized below.
        final g = await api.resume(grant, deviceId: deviceId);
        final url = g.downloadUrl;
        if (url != null && url.isNotEmpty) return url;
      } on ApiException catch (e) {
        // Grant expired / not resumable: fall through to a new grant. A
        // playback conflict is surfaced to the user instead.
        if (e.code == 'PLAYBACK_ACTIVE_STOP_REQUIRED' || e.isPlaybackLeaseHeld) {
          rethrow;
        }
      }
    }
    final stop = _stopPlaybackFor == d.id;
    _stopPlaybackFor = null;
    final g = await api.authorize(
      deviceId: deviceId,
      contentType: d.contentType,
      streamId: d.id,
      containerExtension: d.container,
      title: d.title,
      profileId: _ref.read(sessionProvider).activeProfileId,
      seriesId: d.seriesId,
      posterUrl: d.posterUrl,
      stopPlaybackIfNeeded: stop,
    );
    _put(byId(d.id)!.copyWith(grantId: g.grantId));
    final url = g.downloadUrl;
    if (url == null || url.isEmpty) {
      throw ApiException('Download grant has no source');
    }
    return url;
  }

  void _reportProgress(String? grant, String deviceId, int received, int? total) {
    if (grant == null || grant.isEmpty) return;
    final now = DateTime.now();
    if (now.difference(_lastServerProgress) < const Duration(seconds: 15)) {
      return;
    }
    _lastServerProgress = now;
    unawaited(() async {
      try {
        await _media.downloads.progress(
          grant,
          deviceId: deviceId,
          bytesDownloaded: received,
          bytesTotal: total,
        );
      } catch (_) {}
    }());
  }

  @override
  void dispose() {
    if (PlaybackArbiter.onBeforePlayback == pauseForPlayback) {
      PlaybackArbiter.onBeforePlayback = null;
    }
    if (PlaybackArbiter.onAfterPlayback == playbackEnded) {
      PlaybackArbiter.onAfterPlayback = null;
    }
    _resumeTimer?.cancel();
    _cancel?.cancel();
    unawaited(_policySub?.cancel());
    profileDownloads.dispose();
    super.dispose();
  }
}

final appDownloadsProvider =
    StateNotifierProvider<DownloadsController, List<AppDownload>>(
  DownloadsController.new,
);
