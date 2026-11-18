import 'dart:async';

import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'demo_mode.dart';
import 'library_cloud.dart';
import 'providers.dart' show catalogRepositoryProvider;
import 'session_controller.dart';

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

  int ratingFor(String id) => ratings[id] ?? 0;

  /// A channel is a favourite when it is in My List or in the server
  /// Favourites (TV favourites and the player's heart use those), unless it
  /// was un-liked on this device.
  bool isFavoriteChannel(String id) {
    if (myList.any((e) => e.id == id)) return true;
    final local = ratings[id];
    if (local != null) return local == 1;
    return liked.any((e) => e.id == id);
  }

  double progressFor(String id) {
    for (final e in continueWatching) {
      if (e.id == id) return e.progress ?? 0;
    }
    return 0;
  }

  /// Absolute resume seconds from continue-watching, if known.
  int? resumePositionSecFor(String id) {
    for (final e in continueWatching) {
      if (e.id == id) return e.resumePositionSec;
    }
    return null;
  }
}

class LibraryController extends StateNotifier<LibraryState> {
  LibraryController(this._ref, {bool demo = false})
      : _demo = demo,
        super(const LibraryState()) {
    // Demo: an empty library kept in memory only (no device store, no
    // server), so the demo never shows or changes a signed-out user's data.
    if (demo) {
      state = const LibraryState(ready: true);
      return;
    }
    _bootstrap();
    // Titles from the signed-in account (other devices) show at once.
    LibraryCloud.onPulled = () {
      if (mounted && !state.remoteSynced) _reloadLocal();
    };
  }

  final Ref _ref;
  final bool _demo;
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
    if (_demo) return;
    final session = _ref.read(sessionProvider);
    final profileId = session.activeProfileId;
    if (!session.isLoggedIn ||
        !session.profileSelected ||
        profileId == null ||
        profileId.isEmpty) {
      _syncedProfileId = null;
      _reloadLocal();
      return;
    }
    try {
      final media = _ref.read(mediaRepositoryProvider);
      final results = await Future.wait([
        media.continueWatching(profileId),
        media.myList(profileId),
        media.favorites(profileId),
      ]);
      if (!mounted) return;
      final cw = results[0] as List<ContinueWatchingDto>;
      final list = results[1] as List<ProfileLibraryItemDto>;
      final favs = results[2] as List<ProfileLibraryItemDto>;
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
        // Taps made while this sync was in flight win (17 Oct: a
        // late sync wiped a Like tapped right after a Dislike).
        ratings: {...?_store?.ratingsMap, ...state.ratings},
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

  /// Stub / missing-art rows (e.g. My List "movie-crimson" with no poster):
  /// look up the catalog and replace title + art, or drop unresolvable stubs.
  static bool _isStubLibraryRow(MediaItem e) {
    if (e.kind == MediaKind.live || e.isLive) return false;
    final t = e.title.trim();
    final noArt =
        (e.posterUrl ?? '').isEmpty && (e.backdropUrl ?? '').isEmpty;
    if (t.isEmpty) return true;
    if (t == e.id) return true;
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
    final media = _ref.read(mediaRepositoryProvider);
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

    final cwNeed = [
      for (final e in state.continueWatching)
        if (_isStubLibraryRow(e)) e,
    ];
    final listNeed = [
      for (final e in state.myList)
        if (_isStubLibraryRow(e)) e,
    ];
    if (cwNeed.isEmpty && listNeed.isEmpty) return;

    final resolved = <String, MediaItem>{};
    final drop = <String>{};
    for (final e in [...cwNeed, ...listNeed].take(16)) {
      if (resolved.containsKey(e.id) || drop.contains(e.id)) continue;
      final m = await resolve(e);
      final ok = m != null &&
          m.title.trim().isNotEmpty &&
          m.title.trim() != e.id &&
          !RegExp(r'^(movie|series|vod)[-_]', caseSensitive: false)
              .hasMatch(m.title.trim());
      if (ok) {
        resolved[e.id] = m!;
      } else if (isMockLibraryId(e.id) && listNeed.any((x) => x.id == e.id)) {
        // Sample id from early test builds (e.g. "movie-crimson", client
        // 20 Oct). Real titles are never dropped, even without art.
        drop.add(e.id);
      }
    }
    if (!mounted) return;
    if (resolved.isEmpty && drop.isEmpty) return;

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
    final session = _ref.read(sessionProvider);
    final profileId = session.activeProfileId;
    if (!session.isLoggedIn || profileId == null || profileId.isEmpty) return;
    try {
      await _ref.read(mediaRepositoryProvider).removeMyList(
            profileId: profileId,
            contentType: AppMediaRepository.contentTypeFromKind(MediaKind.movie),
            streamId: id,
          );
    } catch (_) {}
  }

  final Set<String> _myListBusy = {};

  /// My List on the first tap (TV 16 Oct #07, same on mobile): the heart
  /// changes at once and rolls back only if the server refuses; it used to
  /// wait for the round trip and a full reload.
  Future<void> toggleMyList(String id, {MediaItem? item}) async {
    unawaited(FavoriteCategories.remember(id, item?.categoryId));
    if (!_myListBusy.add(id)) return;
    final before = state.myList;
    final adding = !before.any((e) => e.id == id);
    state = state.copyWith(
      myList: adding
          ? [item ?? MediaItem(id: id, title: '', kind: MediaKind.movie), ...before]
          : [for (final e in before) if (e.id != id) e],
    );
    MediaItem? existing;
    for (final e in before) {
      if (e.id == id) existing = e;
    }
    // The title's copy, so My List still shows it after a restart.
    if (adding && item != null) await _remember(item);
    try {
      await _toggleMyListRemote(
        id,
        item: item,
        adding: adding,
        existing: existing,
      );
    } catch (_) {
      if (mounted) state = state.copyWith(myList: before);
    } finally {
      _myListBusy.remove(id);
    }
  }

  /// Server change for [toggleMyList]. Throws when the server refused (the
  /// caller rolls back). Without a session the change is kept on the device.
  Future<void> _toggleMyListRemote(
    String id, {
    MediaItem? item,
    required bool adding,
    MediaItem? existing,
  }) async {
    final session = _ref.read(sessionProvider);
    final profileId = session.activeProfileId;
    if (!session.isLoggedIn ||
        profileId == null ||
        profileId.isEmpty ||
        !state.remoteSynced) {
      await _store?.toggleMyList(id);
      return;
    }
    final media = _ref.read(mediaRepositoryProvider);
    if (!adding) {
      await media.removeMyList(
        profileId: profileId,
        contentType: AppMediaRepository.contentTypeFromKind(
          existing?.kind ?? item?.kind ?? MediaKind.movie,
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
      // Prefer cleaned displayTitle so placeholder "Title" never wins.
      var title = (m?.displayTitle ?? '').trim();
      if (title.isEmpty || title == 'Series' || title.toLowerCase() == 'title') {
        title = (m?.subtitle ?? '').trim();
      }
      if (m == null ||
          title.isEmpty ||
          title == 'Series' ||
          title.toLowerCase() == 'title') {
        // No usable title for the server: keep it on this device.
        await _store?.toggleMyList(id);
        return;
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
  }

  /// Saves the title's copy on the device (never the player's placeholder
  /// title: the stored name is kept instead).
  Future<void> _remember(MediaItem item, {int? positionSec, int? durationSec}) async {
    if (_demo) return;
    final named = isPlaceholderTitle(item.title)
        ? item.withTitle(findKnown(item.id)?.title ?? '')
        : item;
    await _store?.remember(named, positionSec: positionSec, durationSec: durationSec);
  }

  /// The user's own copy of a title (Continue Watching, My List, liked),
  /// for screens whose catalog lookup missed.
  MediaItem? findKnown(String id) {
    for (final e in [
      ...state.continueWatching,
      ...state.myList,
      ...state.liked,
    ]) {
      if (e.id == id && !isPlaceholderTitle(e.title)) return e;
    }
    return null;
  }

  /// The app name is the player's placeholder title when the lookup missed;
  /// never save it as a real title.
  static bool isPlaceholderTitle(String? title) {
    final t = (title ?? '').trim();
    return t.isEmpty || t == AppBrand.name;
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
    if (item != null) await _remember(item, positionSec: positionSec, durationSec: durationSec);

    final session = _ref.read(sessionProvider);
    final profileId = session.activeProfileId;
    if (session.isLoggedIn &&
        profileId != null &&
        profileId.isNotEmpty &&
        durationSec != null &&
        durationSec > 0 &&
        positionSec != null &&
        item != null) {
      try {
        final media = _ref.read(mediaRepositoryProvider);
        await media.saveProgress(
          profileId: profileId,
          contentType: AppMediaRepository.contentTypeFromKind(item.kind),
          streamId: item.id,
          seriesId: item.seriesId,
          episodeId: (item.kind == MediaKind.series &&
                  item.seriesId != null &&
                  item.seriesId!.isNotEmpty)
              ? item.id
              : null,
          title: isPlaceholderTitle(item.title)
              ? (findKnown(item.id)?.displayTitle ?? '')
              : item.displayTitle,
          posterUrl: item.posterUrl ?? findKnown(item.id)?.posterUrl,
          positionSec: positionSec,
          durationSec: durationSec,
        );
      } catch (_) {}
    }

    // On the device only (guest / panel): the rows follow at once.
    if (!state.remoteSynced && !_demo) {
      _reloadLocal();
      return;
    }
    if (!refreshRemote) return;
    if (state.remoteSynced) {
      await syncFromRemote();
    } else {
      _reloadLocal();
    }
  }

  /// Removes a title from Continue Watching (client 10 Nov: long-press on the
  /// card). The card goes at once; if the server refuses, it comes back and
  /// false is returned.
  Future<bool> removeFromContinue(MediaItem item) async {
    final before = state.continueWatching;
    state = state.copyWith(
      continueWatching: [
        for (final e in before)
          if (e.id != item.id) e,
      ],
    );
    if (_demo) return true;
    await _store?.setProgress(item.id, 0);
    final rows = _cwRows[item.id];
    final session = _ref.read(sessionProvider);
    final profileId = session.activeProfileId;
    if (rows == null ||
        rows.isEmpty ||
        !session.isLoggedIn ||
        profileId == null ||
        profileId.isEmpty) {
      return true;
    }
    try {
      final media = _ref.read(mediaRepositoryProvider);
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
    if (state.remoteSynced) {
      state = LibraryState(
        ready: true,
        myList: state.myList,
        continueWatching: state.continueWatching,
        downloads: _store?.downloadItems() ?? const [],
        reminders: state.reminders,
        liked: state.liked,
        ratings: state.ratings,
        remoteSynced: true,
      );
    } else {
      _reloadLocal();
    }
  }

  /// Remind Me: the button changes at once (it used to wait for the item to
  /// resolve from local storage, which often failed, so it looked dead) and
  /// the reminder is saved per profile on the server (backend 16 Oct;
  /// older backends answer 404 and it stays on this device).
  Future<void> toggleReminder(String id, {MediaItem? item}) async {
    final before = state.reminders;
    final on = before.any((e) => e.id == id);
    final m = item ?? (on ? before.firstWhere((e) => e.id == id) : null);
    state = state.copyWith(
      reminders: on
          ? [for (final e in before) if (e.id != id) e]
          : [m ?? MediaItem(id: id, title: '', kind: MediaKind.movie), ...before],
    );
    await _store?.toggleReminder(id);
    final session = _ref.read(sessionProvider);
    final profileId = session.activeProfileId;
    if (!session.isLoggedIn || profileId == null || profileId.isEmpty) return;
    try {
      final extras = _ref.read(mediaRepositoryProvider).extras;
      final type =
          AppMediaRepository.contentTypeFromKind(m?.kind ?? MediaKind.movie);
      if (on) {
        await extras.removeReminder(
          profileId: profileId,
          contentType: type,
          streamId: id,
        );
      } else {
        await extras.addReminder(
          profileId: profileId,
          contentType: type,
          streamId: id,
          seriesId: m?.seriesId,
          title: m?.displayTitle,
          posterUrl: m?.posterUrl,
        );
      }
    } catch (_) {}
  }

  /// Title reminders from the server (no programme time). Null when the
  /// backend has no reminders API. Device-only reminders are uploaded once
  /// when the server list is still empty.
  Future<List<MediaItem>?> _remoteReminders(String profileId) async {
    try {
      final extras = _ref.read(mediaRepositoryProvider).extras;
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
            contentType: AppMediaRepository.contentTypeFromKind(m.kind),
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

  /// Like / Dislike change at once (iPhone, 17 Oct: the button waited for
  /// the server save and then a full library reload, several seconds). The
  /// server Favorites update runs in the background.
  Future<void> setRating(String id, int rating, {MediaItem? item}) async {
    if (rating == 1) unawaited(FavoriteCategories.remember(id, item?.categoryId));
    state = LibraryState(
      ready: state.ready,
      myList: state.myList,
      continueWatching: state.continueWatching,
      downloads: state.downloads,
      reminders: state.reminders,
      liked: state.liked,
      ratings: {...state.ratings, id: rating},
      remoteSynced: state.remoteSynced,
    );
    // Saved on the device at once, so a sync rebuilding from the store
    // keeps the newest tap.
    unawaited(_store?.setRating(id, rating));
    if (item != null) unawaited(_remember(item));
    unawaited(_setRatingRemote(id, rating, item: item));
  }

  Future<void> _setRatingRemote(String id, int rating, {MediaItem? item}) async {
    final session = _ref.read(sessionProvider);
    final profileId = session.activeProfileId;
    if (session.isLoggedIn &&
        profileId != null &&
        profileId.isNotEmpty &&
        state.remoteSynced) {
      final media = _ref.read(mediaRepositoryProvider);
      try {
        MediaItem? m = item;
        if (m == null) {
          for (final e in [...state.myList, ...state.continueWatching, ...state.liked]) {
            if (e.id == id) {
              m = e;
              break;
            }
          }
        }
        if (m != null) {
          final contentType =
              AppMediaRepository.contentTypeFromKind(m.kind);
          if (rating == 1) {
            var title = m.displayTitle.trim();
            if (title.isEmpty ||
                title == 'Series' ||
                title.toLowerCase() == 'title') {
              title = (m.subtitle ?? '').trim();
            }
            if (title.isEmpty ||
                title == 'Series' ||
                title.toLowerCase() == 'title') {
              await _store?.setRating(id, rating);
              _reloadLocal();
              return;
            }
            final streamId = (m.kind == MediaKind.series &&
                    m.seriesId != null &&
                    m.seriesId!.isNotEmpty)
                ? m.seriesId!
                : m.id;
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
              streamId: m.id,
            );
          }
          await syncFromRemote();
          return;
        }
      } catch (_) {
        // Fall through to local.
      }
    }
    await _store?.setRating(id, rating);
    if (state.remoteSynced) {
      state = LibraryState(
        ready: true,
        myList: state.myList,
        continueWatching: state.continueWatching,
        downloads: state.downloads,
        reminders: state.reminders,
        liked: state.liked,
        // Taps made while this sync was in flight win (17 Oct: a
        // late sync wiped a Like tapped right after a Dislike).
        ratings: {...?_store?.ratingsMap, ...state.ratings},
        remoteSynced: true,
      );
    } else {
      _reloadLocal();
    }
  }
}

final libraryProvider =
    StateNotifierProvider<LibraryController, LibraryState>((ref) {
  final ctrl = LibraryController(ref, demo: ref.watch(demoModeProvider));
  ref.listen<SessionState>(sessionProvider, (prev, next) {
    final profileChanged = prev?.activeProfileId != next.activeProfileId;
    final loginChanged = prev?.isLoggedIn != next.isLoggedIn;
    final selectedChanged = prev?.profileSelected != next.profileSelected;
    if (profileChanged || loginChanged || selectedChanged) {
      ctrl.syncFromRemote();
    }
  });
  return ctrl;
});
