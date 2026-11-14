import 'dart:async';

import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'providers.dart' show catalogRepositoryProvider;
import 'tv_session.dart';

class LibraryState {
  const LibraryState({
    this.ready = false,
    this.myList = const [],
    this.continueWatching = const [],
    this.downloads = const [],
    this.reminders = const [],
    this.liked = const [],
    this.ratings = const {},
    this.remoteSynced = false,
  });

  final bool ready;
  final List<MediaItem> myList;
  final List<MediaItem> continueWatching;
  final List<MediaItem> downloads;
  final List<MediaItem> reminders;
  final List<MediaItem> liked;
  final Map<String, int> ratings;
  final bool remoteSynced;

  bool contains(String id) => myList.any((e) => e.id == id);

  LibraryState copyWith({
    List<MediaItem>? myList,
    List<MediaItem>? reminders,
    List<MediaItem>? continueWatching,
    List<MediaItem>? liked,
  }) {
    return LibraryState(
      ready: ready,
      myList: myList ?? this.myList,
      continueWatching: continueWatching ?? this.continueWatching,
      downloads: downloads,
      reminders: reminders ?? this.reminders,
      liked: liked ?? this.liked,
      ratings: ratings,
      remoteSynced: remoteSynced,
    );
  }

  bool isDownloaded(String id) => downloads.any((e) => e.id == id);

  bool hasReminder(String id) => reminders.any((e) => e.id == id);

  /// Local thumbs first; otherwise a title in the server Favorites counts as
  /// liked (Like is stored there, so the button used to stay on "Like").
  int ratingFor(String id) {
    final local = ratings[id];
    if (local != null) return local;
    return liked.any((e) => e.id == id || e.seriesId == id) ? 1 : 0;
  }

  double progressFor(String id) {
    for (final e in continueWatching) {
      if (e.id == id) return e.progress ?? 0;
    }
    return 0;
  }

  int? resumePositionSecFor(String id) {
    for (final e in continueWatching) {
      if (e.id == id) return e.resumePositionSec;
    }
    return null;
  }
}

class LibraryController extends StateNotifier<LibraryState> {
  LibraryController(this._ref) : super(const LibraryState()) {
    _bootstrap();
  }

  final Ref _ref;
  LibraryStore? _store;
  String? _syncedProfileId;

  /// Server Continue Watching rows by card id, kept so a removal saves each
  /// row's own keys (series rows show the episode id). A list: two rows can
  /// show as one card (same id saved under another type), and all must go
  /// or the card comes back on the next sync.
  final Map<String, List<ContinueWatchingDto>> _cwRows = {};

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    _store = LibraryStore(prefs);
    await _store!.ensureSeeded();
    if (!prefs.containsKey('app_reminders_migrated')) {
      await prefs.setBool('app_reminders_migrated', true);
    }
    _reloadLocal();
    await syncFromRemote();
  }

  void _reloadLocal() {
    final store = _store;
    if (store == null) return;
    state = LibraryState(
      ready: true,
      myList: store.myListItems(),
      continueWatching: store.continueWatchingItems(),
      downloads: store.downloadItems(),
      reminders: store.reminderItems(),
      liked: store.likedItems(),
      ratings: store.ratingsMap,
      remoteSynced: false,
    );
  }

  Future<void> syncFromRemote() async {
    final session = _ref.read(tvSessionProvider);
    final profileId = session.activeProfileId;
    if (!session.loggedIn || profileId == null || profileId.isEmpty) {
      _syncedProfileId = null;
      _reloadLocal();
      return;
    }
    try {
      final media = _ref.read(tvMediaRepositoryProvider);
      final cw = await media.continueWatching(profileId);
      final list = await media.myList(profileId);
      final favs = await media.favorites(profileId);
      final reminders = await _remoteReminders(profileId);
      if (!mounted) return;
      final cwItems = cw.map(AppMediaRepository.mediaFromContinue).toList();
      _cwRows.clear();
      for (var i = 0; i < cw.length; i++) {
        (_cwRows[cwItems[i].id] ??= []).add(cw[i]);
      }
      state = LibraryState(
        ready: true,
        myList: list.map(AppMediaRepository.mediaFromLibrary).toList(),
        continueWatching: cwItems,
        downloads: _store?.downloadItems() ?? const [],
        reminders: reminders ?? _store?.reminderItems() ?? const [],
        liked: favs.map(AppMediaRepository.mediaFromLibrary).toList(),
        ratings: _store?.ratingsMap ?? const {},
        remoteSynced: true,
      );
      _syncedProfileId = profileId;
      unawaited(_hydrateLibraryRows());
      unawaited(_hydrateScenes(cw));
      unawaited(_refreshLiveNames());
    } catch (_) {
      if (_syncedProfileId != profileId) {
        _reloadLocal();
      }
    }
  }

  /// Stub / missing-art rows (e.g. My List "movie-crimson"): catalog hydrate
  /// or drop unresolvable stubs (client 20 Oct).
  static bool _isStubLibraryRow(MediaItem e) {
    if (e.kind == MediaKind.live || e.isLive) return false;
    final t = e.title.trim();
    final noArt =
        (e.posterUrl ?? '').isEmpty && (e.backdropUrl ?? '').isEmpty;
    if (t.isEmpty || t == e.id) return true;
    if (RegExp(r'^(movie|series|vod|episode)[-_]', caseSensitive: false)
        .hasMatch(t)) {
      return true;
    }
    return noArt;
  }

  /// Saved live channels show the channel's current name, quality label
  /// included ("MBC 1 RAW"), not the name saved when they were added.
  Future<void> _refreshLiveNames() async {
    final catalog = _ref.read(catalogRepositoryProvider);
    if (catalog is! RemoteCatalogRepository) return;
    final Map<String, MediaItem> current;
    try {
      current = await catalog.currentLiveRows([
        ...state.liked,
        ...state.myList,
        ...state.continueWatching,
      ]);
    } catch (_) {
      return;
    }
    if (!mounted || current.isEmpty) return;
    List<MediaItem> named(List<MediaItem> rows) => [
          for (final e in rows)
            if (current[e.id]?.title.trim() case final t?
                when t.isNotEmpty && t != e.title)
              e.withTitle(t)
            else
              e,
        ];
    state = state.copyWith(
      liked: named(state.liked),
      myList: named(state.myList),
      continueWatching: named(state.continueWatching),
    );
  }

  /// Continue Watching scene images (client 1 Nov #7): rows the server sent
  /// without an episode still / movie backdrop look it up (series info by
  /// episode id, then season + episode; movie info), 4 at a time.
  Future<void> _hydrateScenes(List<ContinueWatchingDto> rows) async {
    final media = _ref.read(tvMediaRepositoryProvider);
    final cache = <String, Future<SeriesDetailDto>>{};
    final need = [
      for (final c in rows.take(20))
        if (pickCleanArt([c.stillUrl, c.backdropUrl]) == null) c,
    ];
    final found = <String, String>{};
    for (var i = 0; i < need.length; i += 4) {
      await Future.wait([
        for (final c in need.skip(i).take(4))
          media
              .continueScene(c, seriesCache: cache)
              .timeout(const Duration(seconds: 8))
              .then((scene) {
            final ep = c.episodeId;
            final id = (ep != null && ep.isNotEmpty) ? ep : c.streamId;
            if (scene != null) found[id] = scene;
          }).catchError((Object _) {}),
      ]);
    }
    if (!mounted || found.isEmpty) return;
    state = state.copyWith(
      continueWatching: [
        for (final e in state.continueWatching)
          if (found[e.id] case final scene?) e.withScene(scene) else e,
      ],
    );
  }

  Future<void> _hydrateLibraryRows() async {
    final catalog = _ref.read(catalogRepositoryProvider);

    Future<MediaItem?> resolve(MediaItem e) async {
      final parent = e.seriesId;
      final key = (parent != null && parent.isNotEmpty) ? parent : e.id;
      try {
        final m = await catalog
            .getById(
              key,
              kind: key == parent ? MediaKind.series : e.kind,
            )
            .timeout(const Duration(seconds: 8));
        if (m == null) return null;
        final title = m.title.trim().isNotEmpty ? m.title : e.title;
        final art = m.posterUrl ?? m.backdropUrl ?? e.posterUrl;
        return MediaItem(
          id: e.id,
          title: title,
          subtitle: m.subtitle ?? e.subtitle,
          titleArabic: m.titleArabic ?? e.titleArabic,
          kind: e.kind,
          year: m.year ?? e.year,
          rating: m.rating ?? e.rating,
          matchPercent: e.matchPercent,
          durationLabel: m.durationLabel ?? e.durationLabel,
          genres: m.genres.isNotEmpty ? m.genres : e.genres,
          badges: m.badges.isNotEmpty ? m.badges : e.badges,
          isOriginal: e.isOriginal,
          isLive: e.isLive,
          progress: e.progress,
          progressLabel: e.progressLabel,
          synopsis: m.synopsis ?? e.synopsis,
          posterSeed: m.posterSeed ?? e.posterSeed,
          posterUrl: art,
          backdropUrl: e.backdropUrl ?? m.backdropUrl ?? art,
          streamUrl: e.streamUrl,
          containerExtension: e.containerExtension,
          categoryId: e.categoryId ?? m.categoryId,
          seriesId: e.seriesId ?? m.seriesId,
          resumePositionSec: e.resumePositionSec,
        );
      } catch (_) {
        return null;
      }
    }

    final need = [
      for (final e in [...state.continueWatching, ...state.myList])
        if (_isStubLibraryRow(e)) e,
    ];
    if (need.isEmpty) return;

    final resolved = <String, MediaItem>{};
    final drop = <String>{};
    for (final e in need.take(16)) {
      if (resolved.containsKey(e.id) || drop.contains(e.id)) continue;
      final m = await resolve(e);
      final ok = m != null &&
          m.title.trim().isNotEmpty &&
          m.title.trim() != e.id &&
          !RegExp(r'^(movie|series|vod)[-_]', caseSensitive: false)
              .hasMatch(m.title.trim());
      if (ok) {
        resolved[e.id] = m!;
      } else if (isMockLibraryId(e.id) && state.myList.any((x) => x.id == e.id)) {
        // Sample id from early test builds (e.g. "movie-crimson", client
        // 20 Oct). Real titles are never dropped, even without art.
        drop.add(e.id);
      }
    }
    if (!mounted || (resolved.isEmpty && drop.isEmpty)) return;

    state = state.copyWith(
      continueWatching: [
        for (final e in state.continueWatching)
          if (resolved[e.id] case final m?) m else e,
      ],
      myList: [
        for (final e in state.myList)
          if (!drop.contains(e.id)) resolved[e.id] ?? e,
      ],
    );
    for (final id in drop) {
      unawaited(_store?.removeFromMyList(id));
      // Also on the server, or the next sync brings it back.
      unawaited(_removeStubRemote(id));
    }
  }

  /// Removes a sample-id row (see [isMockLibraryId]) from the server's My
  /// List. Best effort: failures leave it for the next sync to retry.
  Future<void> _removeStubRemote(String id) async {
    final session = _ref.read(tvSessionProvider);
    final profileId = session.activeProfileId;
    if (!session.loggedIn || profileId == null || profileId.isEmpty) return;
    try {
      await _ref.read(tvMediaRepositoryProvider).removeMyList(
            profileId: profileId,
            contentType: AppMediaRepository.contentTypeFromKind(MediaKind.movie),
            streamId: id,
          );
    } catch (_) {}
  }

  final Set<String> _myListBusy = {};

  /// Optimistic: the button changes on the first press. It used to change
  /// only after two server calls (2–4 s on the TV), so users pressed again
  /// and undid it (client 16 Oct "does not work on the first attempt").
  Future<void> toggleMyList(String id, {MediaItem? item}) async {
    unawaited(FavoriteCategories.remember(id, item?.categoryId));
    if (!_myListBusy.add(id)) return;
    final before = state.myList;
    final adding = !before.any((e) => e.id == id);
    if (adding) {
      state = state.copyWith(
        myList: [item ?? MediaItem(id: id, title: '', kind: MediaKind.movie), ...before],
      );
    } else {
      state = state.copyWith(
        myList: [for (final e in before) if (e.id != id) e],
      );
    }
    try {
      // Removing: use the stored row's kind (vod/series/live) for the API.
      MediaItem? existing;
      for (final e in before) {
        if (e.id == id) existing = e;
      }
      final ok = await _toggleMyListRemote(
        id,
        item: adding ? item : (existing ?? item),
        adding: adding,
      );
      if (!ok && mounted) state = state.copyWith(myList: before);
    } finally {
      _myListBusy.remove(id);
    }
  }

  /// Returns false when the change failed and the optimistic state must be
  /// rolled back.
  Future<bool> _toggleMyListRemote(
    String id, {
    MediaItem? item,
    required bool adding,
  }) async {
    final session = _ref.read(tvSessionProvider);
    final profileId = session.activeProfileId;
    if (session.loggedIn &&
        profileId != null &&
        profileId.isNotEmpty &&
        state.remoteSynced) {
      final media = _ref.read(tvMediaRepositoryProvider);
      try {
        if (!adding) {
          await media.removeMyList(
            profileId: profileId,
            contentType: AppMediaRepository.contentTypeFromKind(
              item?.kind ?? MediaKind.movie,
            ),
            streamId: id,
          );
        } else {
          MediaItem? m = item;
          if (m == null) {
            for (final e in state.continueWatching) {
              if (e.id == id) {
                m = e;
                break;
              }
            }
          }
          if (m == null) {
            await _store?.toggleMyList(id);
            return true;
          }
          var title = m.displayTitle.trim();
          if (title.isEmpty ||
              title == 'Series' ||
              title.toLowerCase() == 'title') {
            title = (m.subtitle ?? '').trim();
          }
          if (title.isEmpty ||
              title == 'Series' ||
              title.toLowerCase() == 'title') {
            await _store?.toggleMyList(id);
            return true;
          }
          await media.addMyList(
            profileId: profileId,
            contentType: AppMediaRepository.contentTypeFromKind(m.kind),
            streamId: m.id,
            title: title,
            posterUrl: m.posterUrl,
          );
        }
        // Refresh in the background; the optimistic state already shows it.
        unawaited(syncFromRemote());
        return true;
      } catch (_) {
        return false;
      }
    }
    await _store?.toggleMyList(id);
    return true;
  }

  Future<void> setProgress(
    String id,
    double progress, {
    MediaItem? item,
    int? positionSec,
    int? durationSec,
    bool refreshRemote = false,
  }) async {
    await _store?.setProgress(id, progress);
    final session = _ref.read(tvSessionProvider);
    final profileId = session.activeProfileId;
    if (session.loggedIn &&
        profileId != null &&
        profileId.isNotEmpty &&
        item != null &&
        positionSec != null &&
        durationSec != null &&
        durationSec > 0) {
      try {
        await _ref.read(tvMediaRepositoryProvider).saveProgress(
              profileId: profileId,
              contentType: AppMediaRepository.contentTypeFromKind(item.kind),
              streamId: item.id,
              seriesId: item.seriesId,
              episodeId: (item.kind == MediaKind.series &&
                      item.seriesId != null &&
                      item.seriesId!.isNotEmpty)
                  ? item.id
                  : null,
              title: item.displayTitle,
              posterUrl: item.posterUrl,
              positionSec: positionSec,
              durationSec: durationSec,
            );
      } catch (_) {}
    }
    if (!refreshRemote) return;
    if (state.remoteSynced) {
      await syncFromRemote();
    } else {
      _reloadLocal();
    }
  }

  /// Removes a title from Continue Watching (client 10 Nov: red / Menu key
  /// on the card, as LG's red key). The card goes at once; if the server
  /// refuses, it comes back and false is returned.
  Future<bool> removeFromContinue(MediaItem item) async {
    final before = state.continueWatching;
    state = state.copyWith(
      continueWatching: [
        for (final e in before)
          if (e.id != item.id) e,
      ],
    );
    await _store?.setProgress(item.id, 0);
    final rows = _cwRows[item.id];
    final session = _ref.read(tvSessionProvider);
    final profileId = session.activeProfileId;
    if (rows == null ||
        rows.isEmpty ||
        !session.loggedIn ||
        profileId == null ||
        profileId.isEmpty) {
      return true;
    }
    try {
      final media = _ref.read(tvMediaRepositoryProvider);
      for (final row in rows) {
        await media.removeFromContinue(profileId, row);
      }
      _cwRows.remove(item.id);
      return true;
    } catch (_) {
      if (mounted) state = state.copyWith(continueWatching: before);
      return false;
    }
  }

  Future<void> toggleDownload(String id) async {
    await _store?.toggleDownload(id);
    _reloadLocal();
  }

  /// Saves / removes a reminder and updates only the reminders list. It used
  /// to reload the whole library from local storage, which replaced the
  /// server My List / Continue Watching and never showed the reminder (the
  /// item could not be resolved), so the button looked dead.
  Future<void> toggleReminder(String id, {MediaItem? item}) async {
    final before = state.reminders;
    final on = before.any((e) => e.id == id);
    state = state.copyWith(
      reminders: on
          ? [for (final e in before) if (e.id != id) e]
          : [item ?? MediaItem(id: id, title: '', kind: MediaKind.movie), ...before],
    );
    await _store?.toggleReminder(id);
    // Server copy per profile (backend 16 Oct reminders API; older backends
    // answer 404 and the reminder stays on this TV only).
    final session = _ref.read(tvSessionProvider);
    final profileId = session.activeProfileId;
    if (!session.loggedIn || profileId == null || profileId.isEmpty) return;
    final m = item ?? (on ? before.firstWhere((e) => e.id == id) : null);
    try {
      final extras = _ref.read(tvMediaRepositoryProvider).extras;
      if (on) {
        await extras.removeReminder(
          profileId: profileId,
          contentType: _contentType(m),
          streamId: id,
        );
      } else {
        await extras.addReminder(
          profileId: profileId,
          contentType: _contentType(m),
          streamId: id,
          seriesId: m?.seriesId,
          title: m?.displayTitle,
          posterUrl: m?.posterUrl,
        );
      }
    } catch (_) {}
  }

  static String _contentType(MediaItem? m) =>
      AppMediaRepository.contentTypeFromKind(m?.kind ?? MediaKind.movie);

  /// Title reminders from the server (no programme time). Null when the
  /// backend has no reminders API. The first time the server list is empty
  /// while this TV has local reminders, they are uploaded once.
  Future<List<MediaItem>?> _remoteReminders(String profileId) async {
    try {
      final extras = _ref.read(tvMediaRepositoryProvider).extras;
      final rows = await extras.reminders(profileId);
      if (rows == null) return null;
      final titles = [
        for (final r in rows)
          if (r.startsAt == null)
            MediaItem(
              id: r.streamId,
              title: r.title ?? '',
              kind: AppMediaRepository.kindFromContentType(r.contentType),
              posterUrl: r.posterUrl,
              seriesId: r.seriesId,
            ),
      ];
      final local = _store?.reminderItems() ?? const <MediaItem>[];
      if (titles.isEmpty && local.isNotEmpty) {
        for (final m in local) {
          await extras.addReminder(
            profileId: profileId,
            contentType: _contentType(m),
            streamId: m.id,
            seriesId: m.seriesId,
            title: m.displayTitle,
            posterUrl: m.posterUrl,
          );
        }
        return local;
      }
      return titles;
    } catch (_) {
      return null;
    }
  }

  /// Like / Dislike. Pressing the active one again clears it. Like is kept
  /// in the server Favorites; un-liking removes it there.
  Future<void> setRating(String id, int rating, {MediaItem? item}) async {
    if (rating == 1) unawaited(FavoriteCategories.remember(id, item?.categoryId));
    final current = state.ratingFor(id);
    final next = rating == current ? 0 : rating;
    await _store?.setRating(id, next);
    _reloadLocalRatings();

    final session = _ref.read(tvSessionProvider);
    final profileId = session.activeProfileId;
    if (!session.loggedIn || profileId == null || profileId.isEmpty) return;
    if (next != 1 && current != 1) return;

    MediaItem? m = item;
    if (m == null) {
      for (final e in [
        ...state.myList,
        ...state.continueWatching,
        ...state.liked,
      ]) {
        if (e.id == id) {
          m = e;
          break;
        }
      }
    }
    if (m == null) return;
    final media = _ref.read(tvMediaRepositoryProvider);
    final contentType = AppMediaRepository.contentTypeFromKind(m.kind);
    final streamId = (m.kind == MediaKind.series &&
            m.seriesId != null &&
            m.seriesId!.isNotEmpty)
        ? m.seriesId!
        : m.id;
    try {
      if (next == 1) {
        var title = m.displayTitle.trim();
        if (title.isEmpty ||
            title == 'Series' ||
            title.toLowerCase() == 'title') {
          title = (m.subtitle ?? '').trim();
        }
        if (title.isEmpty ||
            title == 'Series' ||
            title.toLowerCase() == 'title') {
          await _store?.setRating(id, next);
          _reloadLocalRatings();
          return;
        }
        await media.addFavorite(
          profileId: profileId,
          contentType: contentType,
          streamId: streamId,
          title: title,
          posterUrl: m.posterUrl,
          seriesId: m.seriesId,
          categoryId: m.categoryId ?? FavoriteCategories.categoryOf(m.id),
        );
      } else {
        await media.removeFavorite(
          profileId: profileId,
          contentType: contentType,
          streamId: streamId,
        );
      }
      await syncFromRemote();
    } catch (_) {}
  }

  /// Refresh only the thumbs map (keeps the server lists already loaded).
  void _reloadLocalRatings() {
    final store = _store;
    if (store == null) return;
    state = LibraryState(
      ready: state.ready,
      myList: state.myList,
      continueWatching: state.continueWatching,
      downloads: state.downloads,
      reminders: state.reminders,
      liked: state.liked,
      ratings: store.ratingsMap,
      remoteSynced: state.remoteSynced,
    );
  }
}

final libraryProvider =
    StateNotifierProvider<LibraryController, LibraryState>((ref) {
  final ctrl = LibraryController(ref);
  ref.listen<TvSessionState>(tvSessionProvider, (prev, next) {
    if (prev?.activeProfileId != next.activeProfileId ||
        prev?.loggedIn != next.loggedIn) {
      ctrl.syncFromRemote();
    }
  });
  return ctrl;
});
