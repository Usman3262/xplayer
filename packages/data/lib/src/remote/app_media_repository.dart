import 'sports_api.dart';
import 'package:domain/domain.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'downloads_api.dart';
import 'extras_api.dart';
import 'api_config.dart';
import 'api_exception.dart';
import 'auth_models.dart';
import 'catalog_api.dart';
import 'app_auth_repository.dart';
import 'media_models.dart';
import 'notifications_api.dart';
import 'playback_api.dart';
import 'profiles_api.dart';
import 'token_store.dart';
import 'json_read.dart';

/// Catalog, playback lease, and soft profiles on Usman `/v1`.
class AppMediaRepository {
  AppMediaRepository({
    ApiConfig? config,
    TokenStore? tokenStore,
    ApiClient? client,
  }) {
    final tokens = tokenStore ?? TokenStore();
    final cfg = config ?? ApiConfig.fromEnvironment();
    _client = client ??
        ApiClient(
          config: cfg,
          tokenStore: tokens,
        );
    _catalog = CatalogApi(_client);
    _playback = PlaybackApi(_client);
    _profiles = ProfilesApi(_client);
    downloads = DownloadsApi(_client);
    extras = ExtrasApi(_client);
    sports = SportsApi(_client);
    notifications = NotificationsApi(_client);
  }

  /// Share the authenticated [ApiClient] from auth (refresh + tokens).
  factory AppMediaRepository.fromAuth(AppAuthRepository auth) {
    return AppMediaRepository(client: auth.client);
  }

  late final ApiClient _client;
  late final CatalogApi _catalog;
  late final PlaybackApi _playback;
  late final ProfilesApi _profiles;

  /// Offline downloads (`/v1/downloads/*`).
  late final DownloadsApi downloads;

  /// Match centre: fixtures, lineups, events, statistics (`/v1/sports/*`).
  late final SportsApi sports;

  /// VOD info, live EPG, reminders (backend 16 Oct additions; 404-safe).
  late final ExtrasApi extras;

  /// In-app notification inbox (Control Panel messages + update alerts).
  late final NotificationsApi notifications;

  // —— Catalog ——

  Future<List<CatalogCategoryDto>> liveCategories() =>
      _catalog.liveCategories();

  Future<PageResult<CatalogStreamDto>> liveStreams({
    String? categoryId,
    int limit = 10,
    String? cursor,
  }) async {
    final page = await _catalog.liveStreams(
      categoryId: categoryId,
      limit: limit,
      cursor: cursor,
    );
    return _withoutAds(page, allLive: true);
  }

  Future<List<CatalogCategoryDto>> vodCategories() => _catalog.vodCategories();

  Future<PageResult<CatalogStreamDto>> vodStreams({
    String? categoryId,
    int limit = 10,
    String? cursor,
    String? sort,
  }) {
    return _catalog.vodStreams(
      categoryId: categoryId,
      limit: limit,
      cursor: cursor,
      sort: sort,
    );
  }

  Future<List<CatalogCategoryDto>> seriesCategories() =>
      _catalog.seriesCategories();

  Future<PageResult<CatalogStreamDto>> seriesList({
    String? categoryId,
    int limit = 10,
    String? cursor,
    String? sort,
  }) {
    return _catalog.seriesList(
      categoryId: categoryId,
      limit: limit,
      cursor: cursor,
      sort: sort,
    );
  }

  Future<SeriesDetailDto> seriesDetail(String seriesId) =>
      _catalog.seriesDetail(seriesId);

  Future<PageResult<CatalogStreamDto>> searchCatalog({
    required String q,
    String kind = 'all',
    int limit = 10,
    String? cursor,
    String? categoryId,
  }) async {
    final page = await _catalog.search(
      q: q,
      kind: kind,
      limit: limit,
      cursor: cursor,
      categoryId: categoryId,
    );
    return _withoutAds(page);
  }

  // Provider server-ad / package-header rows must never reach any list,
  // search result, favourite or home row.
  static PageResult<CatalogStreamDto> _withoutAds(
    PageResult<CatalogStreamDto> page, {
    bool allLive = false,
  }) {
    final kept = page.items
        .where(
          (s) =>
              (!allLive && s.contentType != 'live') || !isAdOrHeaderStream(s),
        )
        .toList();
    if (kept.length == page.items.length) return page;
    return PageResult(
      items: kept,
      nextCursor: page.nextCursor,
      total: page.total,
    );
  }

  Future<List<SubscriptionDto>> subscriptions() async {
    final data = await _client.get('/me/subscriptions', auth: true);
    return unwrapListData(data).map(SubscriptionDto.fromJson).toList();
  }

  /// Server's weekly Top 10 (backend #135); throws on a missing / bad answer.
  Future<WeeklyTop10Dto> weeklyTop10() async {
    final data = await _client.get('/catalog/top10', auth: true);
    if (data == null) throw const FormatException('top10: empty answer');
    return WeeklyTop10Dto.fromJson(data);
  }

  Future<bool> sportsEnabled() async {
    final data = await _client.get('/features/sports', auth: true);
    if (data == null) return false;
    return SportsFeatureDto.fromJson(data).enabled;
  }

  Future<List<ContinueWatchingDto>> history(String profileId) =>
      _profiles.history(profileId);

  /// Wide image for a Continue Watching row (client 1 Nov #7): the episode's
  /// own still (by id, then season + episode), else the series backdrop; for
  /// a movie its scene backdrop. TMDB first (no provider logo). Null when no
  /// wide image exists yet; the card then crops the poster until one does.
  Future<String?> continueScene(
    ContinueWatchingDto c, {
    Map<String, Future<SeriesDetailDto>>? seriesCache,
  }) async {
    final own = pickCleanArt([c.stillUrl, c.backdropUrl]);
    if (own != null) return own;
    final kind = kindFromContentType(c.contentType);
    final series = c.seriesId;
    if (series != null && series.isNotEmpty && series != 'null') {
      final f = seriesCache == null
          ? seriesDetail(series)
          : seriesCache.putIfAbsent(series, () => seriesDetail(series));
      final d = await f;
      final still = d.stillFor(
        episodeId: c.episodeId ?? c.streamId,
        season: c.seasonNumber,
        episode: c.episodeNumber,
      );
      return pickCleanArt([still, d.backdropUrl]);
    }
    if (kind == MediaKind.movie) {
      final info = await extras.vodInfo(c.streamId);
      return pickCleanArt([info?.backdropUrl]);
    }
    return null;
  }

  // —— Playback ——

  /// Settings / diagnostics: Redis lease Active · 1/1 or Inactive · 0/1.
  Future<PlaybackLeaseStatusDto> playbackLeaseStatus() =>
      _playback.leaseStatus();

  Future<PlaybackActiveDto> playbackActive() => _playback.active();

  Future<PlaybackSessionDto> startPlayback({
    required String deviceId,
    required String contentType,
    required String streamId,
    String? profileId,
    String? containerExtension,
    int? maxHeight,
    String? tier,
    List<String>? codecs,
    bool force = false,
    String? title,
    String? categoryName,
  }) {
    final ext = containerExtension?.trim();
    if (contentType != 'live' && (ext == null || ext.isEmpty)) {
      debugPrint(
        '[Playback] WARNING: no containerExtension for streamId=$streamId '
        'contentType=$contentType',
      );
    }
    return _playback.start(
      deviceId: deviceId,
      contentType: contentType,
      streamId: streamId,
      profileId: profileId,
      containerExtension: (ext != null && ext.isNotEmpty) ? ext : null,
      maxHeight: maxHeight,
      tier: tier,
      codecs: codecs,
      force: force,
      title: title,
      categoryName: categoryName,
    );
  }

  Future<PlaybackSessionDto> takeoverPlayback({
    required String deviceId,
    required String contentType,
    required String streamId,
    String? profileId,
    String? containerExtension,
    int? maxHeight,
    String? tier,
    List<String>? codecs,
  }) {
    final ext = containerExtension?.trim();
    return _playback.takeover(
      deviceId: deviceId,
      contentType: contentType,
      streamId: streamId,
      profileId: profileId,
      containerExtension: (ext != null && ext.isNotEmpty) ? ext : null,
      maxHeight: maxHeight,
      tier: tier,
      codecs: codecs,
    );
  }

  Future<PlaybackSessionDto> heartbeatPlayback({
    required String playbackId,
    required String deviceId,
    Map<String, Object?>? stats,
    bool? paused,
  }) {
    return _playback.heartbeat(
      playbackId: playbackId,
      deviceId: deviceId,
      stats: stats,
      paused: paused,
    );
  }

  Future<void> reportPlayback(Map<String, Object?> body) =>
      _playback.report(body);

  Future<PlaybackSessionDto> stopPlayback({
    required String playbackId,
    required String deviceId,
  }) {
    return _playback.stop(playbackId: playbackId, deviceId: deviceId);
  }

  // —— Profiles ——

  Future<List<ProfileDto>> listProfiles() => _profiles.list();

  Future<ProfileDto> createProfile({
    required String name,
    String? avatarUrl,
    bool isKids = false,
  }) {
    return _profiles.create(name: name, avatarUrl: avatarUrl, isKids: isKids);
  }

  Future<ProfileDto> updateProfile({
    required String id,
    String? name,
    String? avatarUrl,
    bool? isKids,
    bool? pinLocked,
  }) {
    return _profiles.update(
      id: id,
      name: name,
      avatarUrl: avatarUrl,
      isKids: isKids,
      pinLocked: pinLocked,
    );
  }

  Future<void> deleteProfile(String id) => _profiles.delete(id);

  Future<void> saveProgress({
    required String profileId,
    required String contentType,
    required String streamId,
    String? seriesId,
    String? episodeId,
    required String title,
    String? posterUrl,
    required int positionSec,
    required int durationSec,
  }) {
    return _profiles.saveProgress(
      profileId: profileId,
      contentType: contentType,
      streamId: streamId,
      seriesId: seriesId,
      episodeId: episodeId,
      title: title,
      posterUrl: posterUrl,
      positionSec: positionSec,
      durationSec: durationSec,
    );
  }

  Future<List<ContinueWatchingDto>> continueWatching(String profileId) =>
      _profiles.continueWatching(profileId);

  /// Removes [row] from Continue Watching (client 10 Nov). The server has no
  /// delete and lists only positions above 0, so the row is saved again with
  /// its own keys at position 0, as LG does.
  Future<void> removeFromContinue(String profileId, ContinueWatchingDto row) {
    return _profiles.saveProgress(
      profileId: profileId,
      contentType: row.contentType,
      streamId: row.streamId,
      seriesId: row.seriesId,
      episodeId: row.episodeId,
      title: row.title,
      posterUrl: row.posterUrl,
      positionSec: 0,
      durationSec: row.durationSec,
    );
  }

  Future<List<ProfileLibraryItemDto>> favorites(String profileId) =>
      _profiles.favorites(profileId);

  Future<void> addFavorite({
    required String profileId,
    required String contentType,
    required String streamId,
    String? seriesId,
    required String title,
    String? posterUrl,
    String? categoryId,
  }) {
    return _profiles.addFavorite(
      profileId: profileId,
      contentType: contentType,
      streamId: streamId,
      seriesId: seriesId,
      title: title,
      posterUrl: posterUrl,
      categoryId: categoryId,
    );
  }

  Future<void> removeFavorite({
    required String profileId,
    required String contentType,
    required String streamId,
  }) {
    return _profiles.removeFavorite(
      profileId: profileId,
      contentType: contentType,
      streamId: streamId,
    );
  }

  Future<List<ProfileLibraryItemDto>> myList(String profileId) =>
      _profiles.myList(profileId);

  Future<void> addMyList({
    required String profileId,
    required String contentType,
    required String streamId,
    String? seriesId,
    required String title,
    String? posterUrl,
  }) {
    return _profiles.addMyList(
      profileId: profileId,
      contentType: contentType,
      streamId: streamId,
      seriesId: seriesId,
      title: title,
      posterUrl: posterUrl,
    );
  }

  Future<void> removeMyList({
    required String profileId,
    required String contentType,
    required String streamId,
  }) {
    return _profiles.removeMyList(
      profileId: profileId,
      contentType: contentType,
      streamId: streamId,
    );
  }

  static MediaKind kindFromContentType(String contentType) {
    switch (contentType.toLowerCase()) {
      case 'live':
        return MediaKind.live;
      case 'series':
        return MediaKind.series;
      case 'vod':
      default:
        return MediaKind.movie;
    }
  }

  static String contentTypeFromKind(MediaKind kind) {
    switch (kind) {
      case MediaKind.live:
        return 'live';
      case MediaKind.series:
        return 'series';
      case MediaKind.sports:
      case MediaKind.movie:
        return 'vod';
    }
  }

  /// [upcoming]: from a Coming Soon list (backend `sort=upcoming`).
  static MediaItem mediaFromStream(CatalogStreamDto s, {bool upcoming = false}) {
    final kind = kindFromContentType(s.contentType);
    // Task #143 #9: surface quality / variant ids (A, F, HD, FHD, 4K…).
    final fromName = _qualityTokens(s.name);
    final badges = <String>[
      // Region / language / subtitle code moved out of the title (client
      // 16 Oct: "EG:", "SUB" clutter titles) — kept as a tag.
      // First: posters show the first badge ("Soon" / "قريبًا").
      if (kind != MediaKind.live && (upcoming || isUpcomingTitle(s.rawName) || isUpcomingTitle(s.name))) soonBadge,
      if (kind != MediaKind.live) ...providerTitleTags(s.rawName ?? s.name),
      if (s.resolution != null && s.resolution!.isNotEmpty) s.resolution!,
      ...fromName.where(
        (t) =>
            s.resolution == null ||
            t.toLowerCase() != s.resolution!.toLowerCase(),
      ),
    ];
    final year = int.tryParse(s.year ?? '');
    final rating = double.tryParse(s.rating ?? '');
    final durationLabel =
        formatRuntimeLabel(runtimeMinutesFromDurationSec(s.durationSec));
    return MediaItem(
      id: s.streamId,
      title: cleanDisplayName(s.name, keepQuality: kind == MediaKind.live),
      kind: kind,
      badges: badges,
      isLive: kind == MediaKind.live,
      posterUrl: s.posterUrl,
      backdropUrl: s.posterUrl,
      containerExtension: s.containerExtension,
      categoryId: s.categoryId,
      genres: s.genres,
      synopsis: s.synopsis,
      year: year,
      rating: rating,
      durationLabel: durationLabel,
      addedSec: s.added,
    );
  }

  static LiveChannel liveFromStream(CatalogStreamDto s) {
    return LiveChannel(
      id: s.streamId,
      name: cleanDisplayName(s.name, keepQuality: true),
      code: s.resolution ?? 'LIVE',
      nowTitle: cleanDisplayName(s.name, keepQuality: true),
      nextTitle: '',
      badge: s.resolution,
      imageUrl: s.posterUrl,
      specs: [
        if (s.resolution != null && s.resolution!.isNotEmpty) s.resolution!,
      ],
    );
  }

  /// True for ##### package headers / server ad slots — never show to users.
  static bool isAdOrHeaderStream(CatalogStreamDto s) {
    return isProviderAdOrHeaderChannel(s.name, rawName: s.rawName);
  }

  static MediaItem mediaFromContinue(ContinueWatchingDto c) {
    final kind = kindFromContentType(c.contentType);
    final progress = c.durationSec > 0 ? c.positionSec / c.durationSec : null;
    final episodeId = c.episodeId;
    final parentSeries = c.seriesId;
    return MediaItem(
      id: (episodeId != null && episodeId.isNotEmpty)
          ? episodeId
          : c.streamId,
      title: cleanDisplayName(c.title, keepQuality: kind == MediaKind.live),
      kind: kind,
      posterUrl: c.posterUrl,
      // Wide art only (episode still / movie scene); null until one exists,
      // so the card never treats a portrait poster as a still.
      backdropUrl: pickCleanArt([c.stillUrl, c.backdropUrl]),
      containerExtension: c.containerExtension,
      seriesId: (parentSeries != null &&
              parentSeries.isNotEmpty &&
              parentSeries != 'null')
          ? parentSeries
          : null,
      progress: progress,
      // Retest: elapsed + total so users see where they stopped (not only a bar).
      progressLabel: _continueProgressLabel(c.positionSec, c.durationSec),
      durationLabel: c.durationSec > 0
          ? _fmtClock(c.durationSec)
          : null,
      resumePositionSec: c.positionSec > 0 ? c.positionSec : null,
    );
  }

  static String? _continueProgressLabel(int positionSec, int durationSec) {
    if (positionSec <= 0 && durationSec <= 0) return null;
    final pos = _fmtClock(positionSec.clamp(0, 1 << 30));
    if (durationSec > 0) {
      return '$pos / ${_fmtClock(durationSec)}';
    }
    if (positionSec > 0) return pos;
    return null;
  }

  static String _fmtClock(int totalSec) {
    final s = totalSec < 0 ? 0 : totalSec;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  static MediaItem mediaFromLibrary(ProfileLibraryItemDto i) {
    return MediaItem(
      id: i.streamId,
      title: i.title,
      kind: kindFromContentType(i.contentType),
      posterUrl: i.posterUrl,
      backdropUrl: i.posterUrl,
      seriesId: (i.seriesId != null &&
              i.seriesId!.isNotEmpty &&
              i.seriesId != 'null')
          ? i.seriesId
          : null,
      categoryId: (i.categoryId != null && i.categoryId!.isNotEmpty) ? i.categoryId : null,
    );
  }

  /// Pull quality / variant tokens from raw catalog titles (beIN Sports A/F…).
  static List<String> _qualityTokens(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    final u = raw.toUpperCase();
    final out = <String>[];
    void add(String t) {
      if (!out.contains(t)) out.add(t);
    }

    if (u.contains('4K') || u.contains('UHD')) add('4K');
    if (RegExp(r'\bFHD\b').hasMatch(u) || u.contains('1080')) add('FHD');
    if (RegExp(r'\bHD\b').hasMatch(u) && !out.contains('FHD')) add('HD');
    if (RegExp(r'\bSD\b').hasMatch(u)) add('SD');
    // Client A/B labeling (screenshots). Map legacy F → B; keep A/B.
    final ab = RegExp(r'\b([AB])\b').firstMatch(u);
    if (ab != null) add(ab.group(1)!);
    final letter = RegExp(r'\b([AF])\b').firstMatch(u);
    if (letter != null) {
      final L = letter.group(1)!;
      add(L == 'F' ? 'B' : L);
    }
    // Numbered beIN-style variants: "1" → A, "2" → B when beside SD/HD.
    final numbered = RegExp(
      r'(?:^|[\s|_-])([12])(?:\s*(?:SD|HD|FHD|4K))?\b',
    ).firstMatch(u);
    if (numbered != null && !out.contains('A') && !out.contains('B')) {
      add(numbered.group(1) == '1' ? 'A' : 'B');
    }
    return out;
  }
}

/// Thrown when another device holds the one-stream lease (HTTP 409).
class PlaybackConflictException implements Exception {
  PlaybackConflictException(
    this.message, {
    this.code,
    this.holderDeviceId,
    this.holderPlaybackId,
  });

  final String message;
  final String? code;
  final String? holderDeviceId;
  final String? holderPlaybackId;

  bool get isLeaseHeld =>
      code == 'PLAYBACK_LEASE_HELD' || (code == null || code!.isEmpty);

  @override
  String toString() => message;
}

Future<T> mapPlaybackConflict<T>(Future<T> Function() run) async {
  try {
    return await run();
  } on ApiException catch (e) {
    if (e.statusCode == 409) {
      // Device-cap 409 must not become a lease "Watch here" dialog.
      if (e.isDeviceLimit) rethrow;
      // Admin stop uses the same 409 channel but must not show "another device".
      if (e.isPlaybackStoppedByAdmin) rethrow;
      final code = e.code;
      final isLease = e.isPlaybackLeaseHeld ||
          code == null ||
          code.isEmpty ||
          code == 'DEVICE_LIMIT'; // pre-Usman lease conflict alias
      if (!isLease) rethrow;
      final holder = e.holder;
      throw PlaybackConflictException(
        e.message.isNotEmpty
            ? e.message
            : 'Another device is currently active. Please close the active device before continuing.',
        code: code ?? 'PLAYBACK_LEASE_HELD',
        holderDeviceId: jsonStr(holder?['deviceId']),
        holderPlaybackId: jsonStr(holder?['playbackId']),
      );
    }
    rethrow;
  }
}
