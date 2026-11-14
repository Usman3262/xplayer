import 'package:domain/domain.dart';

import '../local/favorite_categories.dart';

import '../diag/diag.dart';
import '../remote/api_client.dart' show PageResult;
import '../remote/app_media_repository.dart';
import '../remote/media_models.dart';

/// Remote catalog backed by Usman `/v1/catalog/*` (paginated lists).
class RemoteCatalogRepository implements CatalogRepository {
  RemoteCatalogRepository(this._media, {this.profileId});

  final AppMediaRepository _media;
  final String? profileId;

  List<CatalogStreamDto>? _vodCache;
  List<CatalogStreamDto>? _seriesCache;
  List<CatalogStreamDto>? _liveCache;
  Future<List<CatalogStreamDto>>? _vodInflight;
  Future<List<CatalogStreamDto>>? _seriesInflight;
  Future<List<CatalogStreamDto>>? _liveInflight;

  /// Progressive unfiltered VOD/series scan for client-side category filter
  /// when `?categoryId=` returns empty (Xtream category_id often broken).
  /// Shared buffer + single-flight page fetch so serial UI rails reuse pages.
  /// First shelf page scans until it has enough matches or the catalog ends;
  /// load-more stays capped so one scroll does not pull the whole ~14k feed.
  final List<CatalogStreamDto> _vodScanBuffer = [];
  String? _vodScanCursor;
  bool _vodScanDone = false;
  Future<void>? _vodScanInflight;
  final Set<String> _vodClientFilterCats = {};

  final List<CatalogStreamDto> _seriesScanBuffer = [];
  String? _seriesScanCursor;
  bool _seriesScanDone = false;
  Future<void>? _seriesScanInflight;
  final Set<String> _seriesClientFilterCats = {};

  static const _cfPrefix = 'cf:';

  /// Unfiltered catalog pages pulled per browse() load-more call.
  static const _maxScanPagesPerBrowse = 3;

  /// Hard ceiling if a cursor never terminates (full VOD is ~145 pages @100).
  static const _maxScanPagesAbsolute = 500;

  static int? _clientFilterOffset(String? cursor) {
    if (cursor == null || cursor.isEmpty) return 0;
    if (cursor.startsWith(_cfPrefix)) {
      return int.tryParse(cursor.substring(_cfPrefix.length)) ?? 0;
    }
    // Legacy decimal cursors from the first progressive build.
    return int.tryParse(cursor);
  }

  static String _clientFilterCursor(int offset) => '$_cfPrefix$offset';
  final Map<String, SeriesDetailDto> _seriesDetailCache = {};
  final Map<String, Future<SeriesDetailDto>> _seriesDetailInflight = {};

  /// Episode stream id → parent series id.
  final Map<String, String> _episodeSeriesId = {};

  /// Stream/episode id → container extension (mkv, mp4, …).
  final Map<String, String> _streamContainer = {};

  /// Every catalog row we have seen — details/player resolve without re-fetch.
  final Map<String, MediaItem> _itemById = {};

  static const _pageLimit = CatalogPaging.pageSize;
  static const _homeLimit = CatalogPaging.pageSize;

  void _rememberAll(Iterable<MediaItem> items) {
    for (final m in items) {
      _itemById[m.id] = m;
      final ext = m.containerExtension?.trim();
      if (ext != null && ext.isNotEmpty) {
        _streamContainer[m.id] = ext;
      }
    }
  }

  void _rememberStreams(Iterable<CatalogStreamDto> streams) {
    _rememberAll(streams.map(AppMediaRepository.mediaFromStream));
  }

  Future<List<CatalogStreamDto>> _vod() {
    if (_vodCache != null) return Future.value(_vodCache);
    return _vodInflight ??= _media.vodStreams(limit: _homeLimit).then((page) {
      _vodCache = page.items;
      _rememberStreams(page.items);
      return page.items;
      // Also after a failure: a kept failed request made Retry repeat the
      // same error until the app restarted (client 9 Nov).
    }).whenComplete(() => _vodInflight = null);
  }

  Future<List<CatalogStreamDto>> _series() {
    if (_seriesCache != null) return Future.value(_seriesCache);
    return _seriesInflight ??= _media
        .seriesList(limit: _homeLimit)
        .then((page) {
          _seriesCache = page.items;
          _rememberStreams(page.items);
          _seriesInflight = null;
          return page.items;
        })
        .catchError((Object e) {
          // Backend intermittently returns 503 on series — don't kill home/clips.
          // Not cached as empty: the next load tries again (client 9 Nov).
          _seriesInflight = null;
          return const <CatalogStreamDto>[];
        });
  }

  Future<List<CatalogStreamDto>> _live() {
    if (_liveCache != null) return Future.value(_liveCache);
    return _liveInflight ??= _media.liveStreams(limit: _homeLimit).then((page) {
      _liveCache = page.items;
      _rememberStreams(page.items);
      return page.items;
    }).whenComplete(() => _liveInflight = null);
  }

  @override
  Future<HomeFeed> getHomeFeed() async {
    final results = await Future.wait([_vod(), _live(), _series()]);
    final vod = results[0];
    final live = results[1];
    final series = results[2];

    final movies = vod.map(AppMediaRepository.mediaFromStream).toList();
    final seriesItems = series
        .map(AppMediaRepository.mediaFromStream)
        .toList();
    final liveChannels = (await _generalLive(live))
        .map(AppMediaRepository.liveFromStream)
        .toList();

    final hero = movies.isNotEmpty
        ? movies.first
        : (seriesItems.isNotEmpty
              ? seriesItems.first
              : (liveChannels.isNotEmpty
                    ? MediaItem(
                        id: liveChannels.first.id,
                        title: liveChannels.first.name,
                        kind: MediaKind.live,
                        isLive: true,
                        posterUrl: liveChannels.first.imageUrl,
                        badges: liveChannels.first.badge == null
                            ? const []
                            : [liveChannels.first.badge!],
                      )
                    : MediaItem(
                        id: 'empty',
                        title: AppBrand.name,
                        kind: MediaKind.movie,
                        synopsis: 'Catalog is empty for this subscription.',
                      )));

    // Larger pools so home banner can pick 2 movies + 2 series from 4K /
    // recent without starving (client 20 Oct).
    final top10 = [
      ...movies.take(40),
      ...seriesItems.take(40),
    ];
    final arabicOriginals = seriesItems.take(40).toList();

    // Lineups / fixtures: home "matches" is intentionally empty — NEO has
    // no match-data feed. Log so device QA can confirm (client 19 Oct).
    Diag.dev(
      'SPORTS_DATA homeFeed.matches=0 (hardcoded empty; '
      'no fixtures/lineups API). liveChannels=${liveChannels.length}',
    );
    return HomeFeed(
      hero: hero,
      matches: const [],
      // Real CW comes from the library / progress API — never seed with
      // arbitrary VOD rows as stand-in "continue watching".
      continueWatching: const [],
      top10: top10,
      arabicOriginals: arabicOriginals.isNotEmpty
          ? arabicOriginals
          : movies.take(CatalogPaging.pageSize).toList(),
      liveChannels: liveChannels.take(CatalogPaging.pageSize).toList(),
    );
  }

  @override
  Future<List<MediaItem>> getMovies() async {
    final list = await _vod();
    return list.map(AppMediaRepository.mediaFromStream).toList();
  }

  @override
  Future<List<MediaItem>> getSeries() async {
    final list = await _series();
    return list.map(AppMediaRepository.mediaFromStream).toList();
  }

  @override
  Future<List<LiveChannel>> getLiveChannels() async {
    final list = await _live();
    return list
        .where((s) => !AppMediaRepository.isAdOrHeaderStream(s))
        .map(AppMediaRepository.liveFromStream)
        .toList();
  }

  @override
  Future<List<CatalogCategory>> getCategories(MediaKind kind) async {
    final List<CatalogCategoryDto> raw;
    switch (kind) {
      case MediaKind.movie:
      case MediaKind.sports:
        raw = await _media.vodCategories();
      case MediaKind.series:
        raw = await _media.seriesCategories();
      case MediaKind.live:
        raw = await _liveCats();
    }
    // Unique by id, never by name (client 18 Oct #6 "packages missing"):
    // two packages whose cleaned names match ("THMANYAH" / "THMANYAH ●")
    // were merged and the second one, with its content, disappeared.
    // A repeated name is numbered instead.
    final seen = <String>{};
    final names = <String, int>{};
    final out = <CatalogCategory>[];
    for (final c in raw) {
      if (!seen.add(c.id)) continue;
      var label = cleanDisplayName(c.name);
      if (label.isEmpty) label = c.name.trim();
      if (label.isEmpty) continue;
      final key = label.toLowerCase();
      final n = (names[key] ?? 0) + 1;
      names[key] = n;
      if (n > 1) label = '$label $n';
      out.add(CatalogCategory(id: c.id, name: label, isSports: c.isSports));
    }
    return out;
  }

  int _countInCategory(List<CatalogStreamDto> buf, String categoryId) {
    var n = 0;
    for (final s in buf) {
      if (s.categoryId == categoryId) n++;
    }
    return n;
  }

  /// Pull more unfiltered VOD pages until [categoryId] has [need] matches,
  /// the catalog is exhausted, or [maxPages] new pages were fetched this call.
  Future<void> _vodScanUntilMatches(
    String categoryId,
    int need, {
    required int maxPages,
  }) async {
    var pagesThisCall = 0;
    while (!_vodScanDone &&
        _countInCategory(_vodScanBuffer, categoryId) < need &&
        pagesThisCall < maxPages) {
      final existing = _vodScanInflight;
      if (existing != null) {
        await existing;
        // Shared page another rail already paid for — counts toward budget.
        pagesThisCall++;
        continue;
      }
      final run = () async {
        final page = await _media.vodStreams(
          limit: 100,
          cursor: _vodScanCursor,
        );
        if (page.items.isEmpty) {
          _vodScanDone = true;
          return;
        }
        _vodScanBuffer.addAll(page.items);
        _rememberStreams(page.items);
        final next = page.nextCursor;
        if (next == null || next.isEmpty) {
          _vodScanDone = true;
          _vodScanCursor = null;
        } else {
          _vodScanCursor = next;
        }
      }();
      _vodScanInflight = run;
      try {
        await run;
        pagesThisCall++;
      } finally {
        if (identical(_vodScanInflight, run)) _vodScanInflight = null;
      }
    }
  }

  Future<void> _seriesScanUntilMatches(
    String categoryId,
    int need, {
    required int maxPages,
  }) async {
    var pagesThisCall = 0;
    while (!_seriesScanDone &&
        _countInCategory(_seriesScanBuffer, categoryId) < need &&
        pagesThisCall < maxPages) {
      final existing = _seriesScanInflight;
      if (existing != null) {
        await existing;
        pagesThisCall++;
        continue;
      }
      final run = () async {
        final page = await _media.seriesList(
          limit: 100,
          cursor: _seriesScanCursor,
        );
        if (page.items.isEmpty) {
          _seriesScanDone = true;
          return;
        }
        _seriesScanBuffer.addAll(page.items);
        _rememberStreams(page.items);
        final next = page.nextCursor;
        if (next == null || next.isEmpty) {
          _seriesScanDone = true;
          _seriesScanCursor = null;
        } else {
          _seriesScanCursor = next;
        }
      }();
      _seriesScanInflight = run;
      try {
        await run;
        pagesThisCall++;
      } finally {
        if (identical(_seriesScanInflight, run)) _seriesScanInflight = null;
      }
    }
  }

  /// First shelf page: walk until filled or catalog done. Load-more: small budget.
  int _scanPageBudget(int offset) {
    if (offset <= 0) return _maxScanPagesAbsolute;
    return _maxScanPagesPerBrowse;
  }

  Future<CatalogPage<MediaItem>> _browseVodCategoryClientFilter({
    required String categoryId,
    String? cursor,
    required int limit,
  }) async {
    _vodClientFilterCats.add(categoryId);
    final offset = _clientFilterOffset(cursor) ?? 0;
    final need = offset + limit;
    final budget = _scanPageBudget(offset);
    Diag.dev(
      'CATALOG browse VOD categoryId=$categoryId client-filter '
      'offset=$offset need=$need budget=$budget buf=${_vodScanBuffer.length} '
      'done=$_vodScanDone',
    );
    await _vodScanUntilMatches(categoryId, need, maxPages: budget);
    final matched = [
      for (final s in _vodScanBuffer)
        if (s.categoryId == categoryId) s,
    ];
    final slice = matched.skip(offset).take(limit).toList();
    final items = slice.map(AppMediaRepository.mediaFromStream).toList();
    _rememberAll(items);
    final nextOffset = offset + items.length;
    // More buffered, or catalog not exhausted and this page found titles
    // (or mid-scroll load-more). First page with budget=absolute either fills
    // or marks done — so empty + offset 0 means truly empty for that cat.
    final hasMore = nextOffset < matched.length ||
        (!_vodScanDone && (items.isNotEmpty || offset > 0));
    return CatalogPage(
      items: items,
      nextCursor: hasMore ? _clientFilterCursor(nextOffset) : null,
      total: _vodScanDone ? matched.length : null,
    );
  }

  Future<CatalogPage<MediaItem>> _browseSeriesCategoryClientFilter({
    required String categoryId,
    String? cursor,
    required int limit,
  }) async {
    _seriesClientFilterCats.add(categoryId);
    final offset = _clientFilterOffset(cursor) ?? 0;
    final need = offset + limit;
    final budget = _scanPageBudget(offset);
    Diag.dev(
      'CATALOG browse series categoryId=$categoryId client-filter '
      'offset=$offset need=$need budget=$budget buf=${_seriesScanBuffer.length} '
      'done=$_seriesScanDone',
    );
    await _seriesScanUntilMatches(categoryId, need, maxPages: budget);
    final matched = [
      for (final s in _seriesScanBuffer)
        if (s.categoryId == categoryId) s,
    ];
    final slice = matched.skip(offset).take(limit).toList();
    final items = slice.map(AppMediaRepository.mediaFromStream).toList();
    _rememberAll(items);
    final nextOffset = offset + items.length;
    final hasMore = nextOffset < matched.length ||
        (!_seriesScanDone && (items.isNotEmpty || offset > 0));
    return CatalogPage(
      items: items,
      nextCursor: hasMore ? _clientFilterCursor(nextOffset) : null,
      total: _seriesScanDone ? matched.length : null,
    );
  }

  bool _useVodClientFilter(String? categoryId, String? cursor) {
    if (categoryId == null || categoryId.isEmpty) return false;
    // Only categories that already failed `?categoryId=` — do not force every
    // other rail onto the shared unfiltered scan (that walked ~14k titles).
    if (_vodClientFilterCats.contains(categoryId)) return true;
    if (cursor != null && cursor.startsWith(_cfPrefix)) return true;
    return false;
  }

  bool _useSeriesClientFilter(String? categoryId, String? cursor) {
    if (categoryId == null || categoryId.isEmpty) return false;
    if (_seriesClientFilterCats.contains(categoryId)) return true;
    if (cursor != null && cursor.startsWith(_cfPrefix)) return true;
    return false;
  }

  /// Current catalog rows for saved live channels (favourites, My List,
  /// Continue Watching), by id. A saved row keeps the name it had when it
  /// was added; apps before 1 Nov saved it without the quality label
  /// ("MBC 1" for "MBC 1 RAW"), so two versions looked the same. Reads each
  /// row's package until its channels are found (at most [maxPages] pages
  /// per package).
  Future<Map<String, MediaItem>> currentLiveRows(
    Iterable<MediaItem> rows, {
    int maxPages = 10,
  }) async {
    final wanted = <String, Set<String>>{};
    for (final r in rows) {
      if (r.kind != MediaKind.live && !r.isLive) continue;
      final cat = r.categoryId ?? FavoriteCategories.categoryOf(r.id);
      if (cat == null || cat.isEmpty) continue;
      (wanted[cat] ??= <String>{}).add(r.id);
    }
    final out = <String, MediaItem>{};
    for (final entry in wanted.entries) {
      final left = {...entry.value};
      String? cursor;
      try {
        for (var n = 0; n < maxPages && left.isNotEmpty; n++) {
          final page = await browse(
            kind: MediaKind.live,
            categoryId: entry.key,
            cursor: cursor,
            limit: _pageLimit,
          );
          for (final m in page.items) {
            if (left.remove(m.id)) out[m.id] = m;
          }
          if (!page.hasMore) break;
          cursor = page.nextCursor;
        }
      } catch (e) {
        Diag.dev('LIVE current names failed cat=${entry.key} err=$e');
      }
    }
    return out;
  }

  @override
  Future<CatalogPage<MediaItem>> browse({
    required MediaKind kind,
    String? categoryId,
    String? cursor,
    int limit = 10,
  }) async {
    final pageLimit = limit.clamp(1, 100);
    switch (kind) {
      case MediaKind.movie:
      case MediaKind.sports:
        // Never send cf:* cursors to the server — they are local offsets.
        if (_useVodClientFilter(categoryId, cursor)) {
          return _browseVodCategoryClientFilter(
            categoryId: categoryId!,
            cursor: cursor,
            limit: pageLimit,
          );
        }
        final page = await _media.vodStreams(
          categoryId: categoryId,
          limit: pageLimit,
          cursor: cursor,
        );
        if ((categoryId ?? '').isNotEmpty && page.items.isEmpty) {
          // Server category filter empty → progressive local pages (cf: cursors).
          return _browseVodCategoryClientFilter(
            categoryId: categoryId!,
            cursor: cursor,
            limit: pageLimit,
          );
        }
        final items = page.items
            .map(AppMediaRepository.mediaFromStream)
            .toList();
        _rememberAll(items);
        return CatalogPage(
          items: items,
          nextCursor: page.nextCursor,
          total: page.total,
        );
      case MediaKind.series:
        if (_useSeriesClientFilter(categoryId, cursor)) {
          return _browseSeriesCategoryClientFilter(
            categoryId: categoryId!,
            cursor: cursor,
            limit: pageLimit,
          );
        }
        final page = await _media.seriesList(
          categoryId: categoryId,
          limit: pageLimit,
          cursor: cursor,
        );
        if ((categoryId ?? '').isNotEmpty && page.items.isEmpty) {
          return _browseSeriesCategoryClientFilter(
            categoryId: categoryId!,
            cursor: cursor,
            limit: pageLimit,
          );
        }
        final items = page.items
            .map(AppMediaRepository.mediaFromStream)
            .toList();
        _rememberAll(items);
        return CatalogPage(
          items: items,
          nextCursor: page.nextCursor,
          total: page.total,
        );
      case MediaKind.live:
        final page = await _media.liveStreams(
          categoryId: categoryId,
          limit: pageLimit,
          cursor: cursor,
        );
        // Drop ##### package headers / server ad slots (client: never show).
        // Inside one package keep only its own channels: a page that runs
        // past the package's end must not pull in the next packages
        // (client: scrolling a category jumped into the following ones).
        final inCat = (categoryId ?? '').isEmpty
            ? page.items
            : page.items
                .where((s) =>
                    (s.categoryId ?? '').isEmpty || s.categoryId == categoryId)
                .toList();
        var streams = inCat
            .where((s) => !AppMediaRepository.isAdOrHeaderStream(s))
            .toList();
        // Client 5 Nov #9: drop the Thmanyah Blue package's first (advert) channel.
        if (cursor == null && (categoryId ?? '').isNotEmpty && streams.isNotEmpty) {
          try {
            final cat = (await _liveCats()).where((c) => c.id == categoryId).firstOrNull;
            if (cat != null && isPackageWithLeadingAd(cat.name)) streams = streams.sublist(1);
          } catch (_) {}
        }
        final leftCategory =
            (categoryId ?? '').isNotEmpty && inCat.length < page.items.length;
        final items = [
          for (final s in streams)
            MediaItem(
              id: s.streamId,
              title: cleanDisplayName(s.name, keepQuality: true),
              kind: MediaKind.live,
              isLive: true,
              posterUrl: s.posterUrl,
              backdropUrl: s.posterUrl,
              categoryId: s.categoryId,
            ),
        ];
        _rememberAll(items);
        return CatalogPage(
          items: items,
          nextCursor: leftCategory ? null : page.nextCursor,
          total: leftCategory ? null : page.total,
        );
    }
  }

  @override
  Future<List<SportsMatch>> getSportsMatches() async {
    // Option B: live channels in sports categories — no invented scores.
    // NOT real match lineups (no teams XI / kick-off feed from NEO).
    try {
      final cats = await _liveCats();
      final sportsCats = cats.where(_isSportsCategory).toList();
      Diag.dev(
        'SPORTS_DATA getSportsMatches: liveCats=${cats.length} '
        'sportsCats=${sportsCats.length} '
        'names=${sportsCats.take(8).map((c) => c.name).join(" | ")}',
      );
      if (sportsCats.isEmpty) {
        Diag.dev(
          'SPORTS_DATA getSportsMatches: empty — no sports categories '
          '(lineups API: none; this path only maps live channels)',
        );
        return const [];
      }

      final seen = <String>{};
      final out = <SportsMatch>[];
      // Prefer a few sports categories so the tab isn't empty / single-group only.
      // The six categories load together (they ran one after another,
      // ~2 s on Home from Saudi, 19 Oct); order is kept.
      final picked = sportsCats.take(6).toList();
      final pages = await Future.wait([
        for (final cat in picked)
          _media
              .liveStreams(categoryId: cat.id, limit: _pageLimit)
              .then<PageResult<CatalogStreamDto>?>((p) => p)
              .catchError((Object _) => null),
      ]);
      for (var i = 0; i < picked.length; i++) {
        final cat = picked[i];
        final page = pages[i];
        if (page == null) continue;
        for (final s in page.items) {
          // "##### PACKAGE #####" headers are not channels.
          if (AppMediaRepository.isAdOrHeaderStream(s)) continue;
          if (!seen.add(s.streamId)) continue;
          // A sports CHANNEL, not a match: no teams, no score (the cards
          // showed an invented "0 - 0" and the quality as the away team).
          out.add(
            SportsMatch(
              id: s.streamId,
              homeTeam: cleanDisplayName(s.name, keepQuality: true),
              awayTeam: '',
              homeScore: 0,
              awayScore: 0,
              minute: '',
              stadium: cleanDisplayName(cat.name),
              broadcaster: s.resolution ?? '',
              imageUrl: s.posterUrl,
            ),
          );
        }
      }
      final sample = out.take(3).map((m) => m.homeTeam).join(' | ');
      Diag.dev(
        'SPORTS_DATA getSportsMatches: mappedChannels=${out.length} '
        'kind=live_channels_NOT_lineups sample=$sample',
      );
      return out;
    } catch (e) {
      Diag.dev('SPORTS_DATA getSportsMatches FAILED type=${e.runtimeType} err=$e');
      return const [];
    }
  }

  /// Home "Live TV" row without sports (client 18 Oct #9: it listed ALWAN
  /// SPORT / F1 / WWE because the provider's first live page is sports).
  /// When that page is all sports, the first general package fills it.
  Future<List<CatalogCategoryDto>> _liveCategoriesSafe() async {
    try {
      return await _liveCats();
    } catch (_) {
      return const [];
    }
  }

  Future<List<CatalogStreamDto>> _generalLive(
    List<CatalogStreamDto> firstPage,
  ) async {
    final cats = await _liveCategoriesSafe();
    final sportsIds = {
      for (final c in cats)
        if (_isSportsCategory(c)) c.id,
    };
    bool general(CatalogStreamDto s) =>
        !AppMediaRepository.isAdOrHeaderStream(s) &&
        !sportsIds.contains(s.categoryId) &&
        !isSportsName(s.name);
    final kept = firstPage.where(general).toList();
    if (kept.length >= 4) return kept;
    for (final c in cats) {
      if (_isSportsCategory(c)) continue;
      try {
        final page = await _media.liveStreams(categoryId: c.id, limit: _homeLimit);
        final more = page.items.where(general).toList();
        _rememberStreams(page.items);
        if (more.isNotEmpty) return [...kept, ...more];
      } catch (_) {}
      break;
    }
    return kept;
  }

  List<CatalogCategoryDto>? _sportsCats;

  /// Live categories, shared for 2 min. One Home load asked the server for
  /// the same list three times (19 Oct, ~0.4 s each from Saudi).
  Future<List<CatalogCategoryDto>>? _liveCatsFuture;
  DateTime? _liveCatsAt;
  static const _liveCatsTtl = Duration(minutes: 2);

  Future<List<CatalogCategoryDto>> _liveCats() {
    final cached = _liveCatsFuture;
    final at = _liveCatsAt;
    if (cached != null &&
        at != null &&
        DateTime.now().difference(at) < _liveCatsTtl) {
      return cached;
    }
    final next = _media.liveCategories();
    _liveCatsFuture = next;
    _liveCatsAt = DateTime.now();
    // A failed load is not cached.
    next.catchError((Object _) {
      if (identical(_liveCatsFuture, next)) {
        _liveCatsFuture = null;
        _liveCatsAt = null;
      }
      return const <CatalogCategoryDto>[];
    });
    return next;
  }

  Future<List<CatalogCategoryDto>> _sportsCategories() async {
    final cached = _sportsCats;
    if (cached != null) return cached;
    final cats = await _liveCats();
    final sports = cats.where(_isSportsCategory).toList();
    _sportsCats = sports;
    return sports;
  }

  SportsMatch _sportsMatch(CatalogStreamDto stream, String stadium) {
    return SportsMatch(
      id: stream.streamId,
      homeTeam: stream.name,
      awayTeam: stream.resolution ?? 'LIVE',
      homeScore: 0,
      awayScore: 0,
      minute: 'Live',
      stadium: stadium,
      broadcaster: AppBrand.name,
      imageUrl: stream.posterUrl,
    );
  }

  @override
  Future<CatalogPage<SportsMatch>> browseSports({
    String? cursor,
    int limit = 10,
  }) async {
    final cats = await _sportsCategories();
    if (cats.isEmpty) return const CatalogPage(items: []);

    var index = 0;
    String? streamCursor;
    if (cursor != null && cursor.isNotEmpty) {
      final bar = cursor.indexOf('|');
      if (bar >= 0) {
        index = int.tryParse(cursor.substring(0, bar)) ?? 0;
        final rest = cursor.substring(bar + 1);
        if (rest.isNotEmpty) streamCursor = rest;
      } else {
        index = int.tryParse(cursor) ?? 0;
      }
    }
    if (index < 0) index = 0;

    var hops = 0;
    while (index < cats.length && hops < cats.length) {
      hops++;
      final cat = cats[index];
      final page = await _media.liveStreams(
        categoryId: cat.id,
        limit: limit,
        cursor: streamCursor,
      );
      final items = [
        for (final stream in page.items) _sportsMatch(stream, cat.name),
      ];
      final nextStream = page.nextCursor;
      final moreHere =
          nextStream != null &&
          nextStream.isNotEmpty &&
          nextStream != streamCursor &&
          items.length >= limit;
      if (items.isNotEmpty) {
        String? next;
        if (moreHere) {
          next = '$index|$nextStream';
        } else if (index + 1 < cats.length) {
          next = '${index + 1}|';
        }
        return CatalogPage(items: items, nextCursor: next, total: page.total);
      }
      index++;
      streamCursor = null;
    }
    return const CatalogPage(items: []);
  }

  @override
  Future<List<SportsMatch>> searchSports(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final cats = await _sportsCategories();
    final ids = {for (final cat in cats) cat.id};
    final names = {for (final cat in cats) cat.id: cat.name};
    final items = await search(q, kind: MediaKind.live);
    return [
      for (final item in items)
        if (isSportsHit(item, ids))
          SportsMatch(
            id: item.id,
            homeTeam: item.displayTitle,
            awayTeam: 'LIVE',
            homeScore: 0,
            awayScore: 0,
            minute: 'Live',
            stadium: names[item.categoryId] ?? 'LIVE',
            broadcaster: AppBrand.name,
            imageUrl: item.posterUrl ?? item.backdropUrl,
          ),
    ];
  }

  /// Sports category/channel name. Not bare "bein": beIN Entertainment,
  /// beIN Movies and beIN OD are not sports (they showed in the Sports tab);
  /// beIN Sports names contain "sport" anyway. Arabic: رياضة/رياضية, كرة.
  /// Sports networks and leagues by name (client 18 Oct #9: a sports
  /// package was first in general Live TV). Brands the provider uses for
  /// sports packages are listed, so they go to Sports even when the
  /// server's sports list does not name them.
  static final _sportsWords = RegExp(
    // Not "bein" / "alwan" alone: beIN MOVIES, beIN ENTERTAINMENT and the
    // Alwan drama packages are not sports (their sports packages say SPORT).
    r'sport|uefa|football|soccer|\bkass\b|al[\s-]?kass|dazn|thmanyah|'
    r'\bssc\b|\bad sports?\b|premier league|la ?liga|serie a|'
    r'bundesliga|champions league|\bnba\b|\bnfl\b|\bufc\b|\bwwe\b|'
    r'\bf1\b|formula ?1|motogp|tennis|golf|cricket',
    caseSensitive: false,
  );

  static bool isSportsName(String name) {
    return _sportsWords.hasMatch(name) ||
        name.contains('رياض') ||
        name.contains('كرة') ||
        name.contains('الكأس') ||
        name.contains('دوري') ||
        name.contains('ثمانية') ||
        name.contains('أبطال') ||
        name.contains('⚽');
  }

  /// True when a search row is a sports channel the package may not include.
  static bool isSportsHit(MediaItem item, Set<String> sportsCategoryIds) {
    if (item.kind == MediaKind.sports) return true;
    // Favourites from the server have no category: use the one recorded on
    // this device when the channel was favourited (client 21 Oct).
    final categoryId = item.categoryId ?? FavoriteCategories.categoryOf(item.id);
    if (categoryId != null && sportsCategoryIds.isNotEmpty) {
      return sportsCategoryIds.contains(categoryId);
    }
    return isSportsName(item.title);
  }

  // Server flag OR the name rule: the server only knows its configured
  // list and "sport" in the name.
  static bool _isSportsCategory(CatalogCategoryDto c) =>
      (c.isSports ?? false) || isSportsName(c.name);

  /// Sports tab membership of a live category (client 16 Oct #11): the
  /// backend flag when present (covers AL-KASS, DAZN, ... set by the
  /// operator), else the name rule.
  static bool isSportsCategory(CatalogCategory c) =>
      (c.isSports ?? false) || isSportsName(c.name);

  @override
  Future<List<MediaItem>> getMyList() async {
    final pid = profileId;
    if (pid == null || pid.isEmpty) return const [];
    final list = await _media.myList(pid);
    return list.map(AppMediaRepository.mediaFromLibrary).toList();
  }

  @override
  Future<List<MediaItem>> search(String query, {MediaKind? kind}) async {
    final page = await searchPage(query, kind: kind, limit: _pageLimit);
    return page.items;
  }

  @override
  Future<CatalogPage<MediaItem>> searchPage(
    String query, {
    MediaKind? kind,
    String? cursor,
    int limit = 40,
    String? categoryId,
  }) async {
    final q = query.trim();
    // Inside one package (client 18 Oct TV #9): the server filters by
    // categoryId; the client filter keeps results in the package even on
    // a server without that parameter.
    bool inPackage(String? cat) =>
        categoryId == null || categoryId.isEmpty || cat == categoryId;
    if (q.isEmpty) {
      return const CatalogPage(items: []);
    }
    final kindParam = switch (kind) {
      MediaKind.movie => 'vod',
      MediaKind.series => 'series',
      // Sports are live channels; the screen keeps the sports ones.
      MediaKind.live || MediaKind.sports => 'live',
      null => 'all',
    };
    final pageLimit = limit.clamp(1, 100);
    try {
      final page = await _media.searchCatalog(
        q: q,
        kind: kindParam,
        limit: pageLimit,
        cursor: cursor,
        categoryId: categoryId,
      );
      final items = page.items
          .where((s) => !AppMediaRepository.isAdOrHeaderStream(s))
          .where((s) => inPackage(s.categoryId))
          .map(AppMediaRepository.mediaFromStream)
          .toList();
      _rememberAll(items);
      return CatalogPage(
        items: items,
        nextCursor: page.nextCursor,
        total: page.total,
      );
    } catch (_) {
      // Fallback: local filter of cached pages (no further cursor).
      if (cursor != null && cursor.isNotEmpty) {
        return const CatalogPage(items: []);
      }
      final all = <MediaItem>[
        if (kind == null || kind == MediaKind.movie) ...await getMovies(),
        if (kind == null || kind == MediaKind.series) ...await getSeries(),
        if (kind == null || kind == MediaKind.live) ...[
          for (final c in await getLiveChannels())
            MediaItem(
              id: c.id,
              title: c.name,
              kind: MediaKind.live,
              isLive: true,
              posterUrl: c.imageUrl,
            ),
        ],
      ];
      final lower = q.toLowerCase();
      final filtered = all
          .where((m) => inPackage(m.categoryId))
          .where((m) => m.title.toLowerCase().contains(lower))
          .take(pageLimit)
          .toList(growable: false);
      return CatalogPage(items: filtered);
    }
  }

  @override
  Future<MediaItem?> getById(String id, {MediaKind? kind}) async {
    final cached = _itemById[id];
    if (cached != null) return cached;

    for (final m in _vodCache ?? const <CatalogStreamDto>[]) {
      if (m.streamId == id) {
        final item = AppMediaRepository.mediaFromStream(m);
        _rememberAll([item]);
        return item;
      }
    }
    for (final m in _seriesCache ?? const <CatalogStreamDto>[]) {
      if (m.streamId == id) {
        final item = AppMediaRepository.mediaFromStream(m);
        _rememberAll([item]);
        return item;
      }
    }
    for (final c in _liveCache ?? const <CatalogStreamDto>[]) {
      if (c.streamId == id) {
        final item = MediaItem(
          id: c.streamId,
          title: c.name,
          kind: MediaKind.live,
          isLive: true,
          posterUrl: c.posterUrl,
        );
        _rememberAll([item]);
        return item;
      }
    }

    final parentSeriesId = _episodeSeriesId[id];
    if (parentSeriesId != null && parentSeriesId != id) {
      final parent = _itemById[parentSeriesId];
      if (parent != null) return parent;
      final detail = _seriesDetailCache[parentSeriesId];
      if (detail != null) return _rememberSeries(detail);
    }

    if (kind != null && kind != MediaKind.series) return null;

    try {
      final detail = await _seriesDetail(id);
      if (_isEpisodeStub(detail)) return null;
      if (detail.seriesId.isNotEmpty && detail.seriesId != id) {
        return _itemById[detail.seriesId] ?? _rememberSeries(detail);
      }
      return _rememberSeries(detail);
    } catch (e, st) {
      Diag.err('DETAILS_LOAD_FAILED id=$id kind=${kind?.name ?? '-'}', e, st);
      return null;
    }
  }

  @override
  String? knownContainerExtension(String streamId) {
    final cached = _streamContainer[streamId];
    if (cached != null && cached.isNotEmpty) return cached;
    return _itemById[streamId]?.containerExtension;
  }

  @override
  String? knownSeriesIdForEpisode(String episodeId) {
    final parent = _episodeSeriesId[episodeId];
    if (parent == null || parent.isEmpty || parent == episodeId) return null;
    return parent;
  }

  MediaItem _rememberSeries(SeriesDetailDto detail) {
    final item = MediaItem(
      id: detail.seriesId,
      title: detail.name,
      kind: MediaKind.series,
      synopsis: detail.plot,
      posterUrl: detail.posterUrl,
      backdropUrl: detail.posterUrl,
    );
    if (detail.seriesId.isNotEmpty) _itemById[detail.seriesId] = item;
    return item;
  }

  void _indexEpisodes(SeriesDetailDto detail) {
    if (detail.seriesId.isEmpty || _isEpisodeStub(detail)) return;
    for (final season in detail.seasons) {
      for (final ep in season.episodes) {
        if (ep.id.isEmpty || ep.id == detail.seriesId) continue;
        _episodeSeriesId[ep.id] = detail.seriesId;
        final ext = ep.containerExtension?.trim();
        if (ext != null && ext.isNotEmpty) {
          _streamContainer[ep.id] = ext;
        }
      }
    }
  }

  /// Xtream episode ids are not series — `/catalog/series/{episodeId}` often
  /// returns `{ name: Untitled, seasons: [] }`.
  static bool _isEpisodeStub(SeriesDetailDto d) {
    final emptySeasons =
        d.seasons.isEmpty || d.seasons.every((s) => s.episodes.isEmpty);
    if (!emptySeasons) return false;
    final name = d.name.trim();
    return name.isEmpty ||
        name.toLowerCase() == 'untitled' ||
        d.posterUrl == null;
  }

  Future<SeriesDetailDto> _seriesDetail(String id) {
    final indexed = _episodeSeriesId[id];
    final key = (indexed != null && indexed.isNotEmpty && indexed != id)
        ? indexed
        : id;
    final cached = _seriesDetailCache[key];
    if (cached != null) return Future.value(cached);
    return _seriesDetailInflight[key] ??= _loadSeriesDetail(key);
  }

  Future<SeriesDetailDto> _loadSeriesDetail(String id) async {
    try {
      final detail = await _media.seriesDetail(id);
      if (!_isEpisodeStub(detail)) {
        final seriesId = detail.seriesId.isNotEmpty ? detail.seriesId : id;
        _seriesDetailCache[seriesId] = detail;
        _seriesDetailCache[id] = detail;
        _indexEpisodes(detail);
        _rememberSeries(detail);
      }
      return detail;
    } finally {
      _seriesDetailInflight.remove(id);
    }
  }

  @override
  Future<List<String>> getGenres() async {
    final vod = await _media.vodCategories();
    final series = await _media.seriesCategories();
    final seen = <String>{};
    final out = <String>[];
    for (final c in [...vod, ...series]) {
      final label = cleanDisplayName(c.name);
      if (label.isEmpty) continue;
      if (!seen.add(label.toLowerCase())) continue;
      out.add(label);
    }
    out.sort();
    return out;
  }

  @override
  Future<List<MediaItem>> getByGenre(String genre) async {
    final g = genre.toLowerCase();
    final vodCats = await _media.vodCategories();
    for (final c in vodCats) {
      if (c.name.toLowerCase() == g) {
        final page = await _media.vodStreams(
          categoryId: c.id,
          limit: _pageLimit,
        );
        return page.items.map(AppMediaRepository.mediaFromStream).toList();
      }
    }
    final seriesCats = await _media.seriesCategories();
    for (final c in seriesCats) {
      if (c.name.toLowerCase() == g) {
        final page = await _media.seriesList(
          categoryId: c.id,
          limit: _pageLimit,
        );
        return page.items.map(AppMediaRepository.mediaFromStream).toList();
      }
    }
    return const [];
  }

  @override
  Future<List<Episode>> getEpisodes(String seriesId, {int season = 1}) async {
    final indexed = _episodeSeriesId[seriesId];
    final resolved =
        (indexed != null && indexed.isNotEmpty && indexed != seriesId)
        ? indexed
        : seriesId;
    final detail = await _seriesDetail(resolved);
    SeriesSeasonDto? match;
    for (final s in detail.seasons) {
      if (int.tryParse(s.season.trim()) == season || s.season == '$season') {
        match = s;
        break;
      }
    }
    // Season 1 is only the default before the season list is known: map it
    // to the first real season (a series may start at 0 or 2). Any other
    // missing season is empty — it used to fall back to the first season, so
    // tab "Season 2" of a [1, 3] series showed season 1 again.
    if (match == null && season == 1) {
      final nums = _seasonNumbersOf(detail);
      if (nums.isNotEmpty) {
        for (final s in detail.seasons) {
          if (int.tryParse(s.season.trim()) == nums.first) {
            match = s;
            break;
          }
        }
      }
    }
    if (match == null) return const [];
    final seasonNum = int.tryParse(match.season.trim()) ?? season;
    return [
      for (final e in _inEpisodeOrder(match.episodes))
        Episode(
          id: e.id,
          seriesId: detail.seriesId.isNotEmpty ? detail.seriesId : resolved,
          season: seasonNum,
          number: e.episodeNum ?? 0,
          // Provider code prefixes too ("SHAM: … - S01E01").
          title: cleanDisplayName(e.title),
          synopsis: e.plot,
          stillUrl: e.stillUrl,
          durationLabel:
              formatRuntimeLabel(runtimeMinutesFromDurationSec(e.durationSec)) ??
                  '',
          containerExtension: e.containerExtension,
        ),
    ];
  }

  @override
  Future<int> getSeasonCount(String id) async {
    final indexed = _episodeSeriesId[id];
    final resolved = (indexed != null && indexed.isNotEmpty && indexed != id)
        ? indexed
        : id;
    final detail = await _seriesDetail(resolved);
    final nums = _seasonNumbersOf(detail);
    return nums.isEmpty ? 1 : nums.length;
  }

  @override
  Future<List<int>> getSeasonNumbers(String id) async {
    final indexed = _episodeSeriesId[id];
    final resolved = (indexed != null && indexed.isNotEmpty && indexed != id)
        ? indexed
        : id;
    return _seasonNumbersOf(await _seriesDetail(resolved));
  }

  /// A season's episodes by episode number (client 10 Nov: next / previous
  /// went the wrong way because some series come newest first). Only when
  /// every episode has a number; otherwise the provider order stays. Equal
  /// numbers keep their provider order.
  static List<SeriesEpisodeDto> _inEpisodeOrder(List<SeriesEpisodeDto> eps) {
    if (eps.length < 2 || eps.any((e) => e.episodeNum == null)) return eps;
    final indexed = [for (var i = 0; i < eps.length; i++) (i, eps[i])];
    indexed.sort((a, b) {
      final byNum = a.$2.episodeNum!.compareTo(b.$2.episodeNum!);
      return byNum != 0 ? byNum : a.$1.compareTo(b.$1);
    });
    return [for (final p in indexed) p.$2];
  }

  /// Provider season keys that hold episodes, numeric, ascending, unique.
  static List<int> _seasonNumbersOf(SeriesDetailDto detail) {
    final nums = <int>{};
    for (final s in detail.seasons) {
      if (s.episodes.isEmpty) continue;
      final n = int.tryParse(s.season.trim());
      if (n != null) nums.add(n);
    }
    return nums.toList()..sort();
  }

  @override
  Future<List<MediaItem>> getRelated(String id) async {
    final item = await getById(id);
    if (item == null) return const [];
    final series = item.kind == MediaKind.series;
    // Client 21 Oct (A14): "More Like This" showed the same first titles for
    // every movie / series. Candidates now come from the title's own category
    // plus the general list, ranked by shared genres, same category, year and
    // rating (relatedScore).
    final candidates = <String, MediaItem>{};
    final cat = item.categoryId;
    if (cat != null && cat.isNotEmpty) {
      try {
        final page = series
            ? await _media.seriesList(categoryId: cat, limit: 60)
            : await _media.vodStreams(categoryId: cat, limit: 60);
        for (final m in page.items.map(AppMediaRepository.mediaFromStream)) {
          candidates[m.id] = m;
        }
      } catch (_) {
        // category page unavailable: the general list still works
      }
    }
    final pool = series ? await getSeries() : await getMovies();
    for (final m in pool) {
      candidates.putIfAbsent(m.id, () => m);
    }
    candidates.remove(id);
    if (item.seriesId != null) candidates.remove(item.seriesId);
    final ranked = candidates.values.toList()
      ..sort((a, b) {
        final byScore = relatedScore(item, b).compareTo(relatedScore(item, a));
        if (byScore != 0) return byScore;
        return (b.rating ?? 0).compareTo(a.rating ?? 0);
      });
    _rememberAll(ranked);
    return ranked.take(CatalogPaging.pageSize).toList();
  }

  /// How alike [other] is to [base] for "More Like This": shared genres
  /// count most, then the same category, a close year and a good rating.
  static double relatedScore(MediaItem base, MediaItem other) {
    final mine = _genreSet(base.genres);
    final theirs = _genreSet(other.genres);
    final shared = mine.intersection(theirs).length;
    var score = shared * 4.0;
    if (mine.isNotEmpty && shared == mine.length && shared > 0) score += 2; // same genre mix
    if (base.categoryId != null && base.categoryId == other.categoryId) score += 3;
    if (base.year != null && other.year != null) {
      final gap = (base.year! - other.year!).abs();
      if (gap <= 2) {
        score += 1.5;
      } else if (gap <= 5) {
        score += 0.75;
      }
    }
    score += ((other.rating ?? 0).clamp(0, 10)) / 10;
    return score;
  }

  /// "Action, Drama" / "Action & Adventure" / "دراما" → normalised genre words.
  static Set<String> _genreSet(List<String> genres) {
    final out = <String>{};
    for (final g in genres) {
      for (final part in g.split(RegExp(r'[,/&|،]+'))) {
        final t = part.trim().toLowerCase();
        if (t.isNotEmpty && t != 'and') out.add(t);
      }
    }
    return out;
  }

  @override
  Future<List<MediaItem>> getTrending() async {
    final movies = await getMovies();
    // Coming Soon titles only in their own row (client 4 Nov, as on LG).
    return movies.where((m) => !m.isUpcoming).take(CatalogPaging.pageSize).toList();
  }

  @override
  Future<List<MediaItem>> getNewReleases() => _newest(MediaKind.movie);

  @override
  Future<List<MediaItem>> getNewSeries() => _newest(MediaKind.series);

  /// Client 18 Oct #14: New & Popular showed the first rows of the catalog.
  /// `sort=new` asks the backend for newest first; the client sort keeps the
  /// order right if a page arrives unsorted.
  Future<List<MediaItem>> _newest(MediaKind kind) async {
    final all = await _newestAll(kind);
    // Coming Soon titles only in their own row (client 4 Nov, as on LG).
    // Titles the provider gives no poster stay out of the Home rows (client
    // 10 Nov: blank cards in Recently Added); categories and search still
    // list them.
    final items = all
        .where((m) => !m.isUpcoming && (m.posterUrl ?? '').trim().isNotEmpty)
        .toList();
    // Client 21 Oct A13: the row must change, not stay fixed. The 3 newest
    // stay first; the rest rotates daily among the next newest titles.
    return RotatingPicks.newestWithRotation(
      items,
      idOf: (m) => m.id,
      now: DateTime.now(),
      count: CatalogPaging.pageSize,
      salt: kind.name,
    );
  }

  /// The provider's 60 newest titles of [kind], newest first, not rotated.
  Future<List<MediaItem>> _newestAll(MediaKind kind) async {
    final page = kind == MediaKind.series
        ? await _media.seriesList(limit: 60, sort: 'new')
        : await _media.vodStreams(limit: 60, sort: 'new');
    final rows = [...page.items];
    if (rows.any((r) => r.added != null)) {
      rows.sort((a, b) => (b.added ?? 0).compareTo(a.added ?? 0));
    }
    final all = rows.map(AppMediaRepository.mediaFromStream).toList();
    _rememberAll(all);
    return all;
  }

  /// Top 10 Movies / Series ([Top10]): the same titles in the same order on
  /// every platform (client 10–11 Nov). From the newest 60, not from the
  /// rotated Recently Added row; Kids categories left out, as on LG.
  Future<List<MediaItem>> top10(MediaKind kind) async {
    final series = kind == MediaKind.series;
    // The server's weekly list first (Usman 12 Nov, backend #135): the same
    // on every device and platform. The app's own rule below is the fallback
    // when the call fails or the answer is not usable.
    try {
      final w = await _weeklyTop10();
      final items = (series ? w.series : w.movies)
          .map(AppMediaRepository.mediaFromStream)
          .take(Top10.count)
          .toList();
      _rememberAll(items);
      return items;
    } catch (_) {}
    final weekStart = Top10.weekStart(DateTime.now());
    final results = await Future.wait<Object>([
      _newestBefore(series, weekStart),
      (series ? _media.seriesCategories() : _media.vodCategories())
          .catchError((Object _) => const <CatalogCategoryDto>[]),
    ]);
    final newest = results[0] as List<MediaItem>;
    final cats = results[1] as List<CatalogCategoryDto>;
    final kids = <String>{
      for (final c in cats)
        if (_isKidsCategoryName(c.name) ||
            _isKidsCategoryName(cleanDisplayName(c.name)))
          c.id,
    };
    return Top10.pick(newest, excludeCategoryIds: kids, weekStart: weekStart);
  }

  WeeklyTop10Dto? _weekly;
  Future<WeeklyTop10Dto>? _weeklyInflight;

  /// When Top 10 should be loaded again: the server's next list
  /// (`nextUpdateAt`), else the next Friday 00:00 Saudi time (local rule).
  DateTime get top10NextUpdate =>
      _weekly?.nextUpdateAt ??
      Top10.weekStart(DateTime.now()).add(const Duration(days: 7));

  /// One call for Movies and Series, kept until the server's next list.
  Future<WeeklyTop10Dto> _weeklyTop10() {
    final cached = _weekly;
    final next = cached?.nextUpdateAt;
    if (cached != null && next != null && DateTime.now().toUtc().isBefore(next)) {
      return Future.value(cached);
    }
    return _weeklyInflight ??= _media.weeklyTop10().then((w) {
      // Both lists empty: not a usable week (the app's rule is used instead).
      if (w.movies.isEmpty && w.series.isEmpty) {
        throw const FormatException('top10: both lists empty');
      }
      _weekly = w;
      return w;
    }).whenComplete(() => _weeklyInflight = null);
  }

  /// The newest titles, newest first, enough to hold [Top10.poolSize] added
  /// before [weekStart]: the backend sends at most 100 per page, and a busy
  /// week can fill the first page, so one more page is read if needed.
  Future<List<MediaItem>> _newestBefore(bool series, DateTime weekStart) async {
    final rows = <CatalogStreamDto>[];
    String? cursor;
    for (var page = 0; page < 2; page++) {
      final r = series
          ? await _media.seriesList(limit: 100, sort: 'new', cursor: cursor)
          : await _media.vodStreams(limit: 100, sort: 'new', cursor: cursor);
      rows.addAll(r.items);
      final before =
          rows.where((x) => Top10.addedBefore(x.added, weekStart)).length;
      if (before >= Top10.poolSize || !r.hasMore || r.items.isEmpty) break;
      cursor = r.nextCursor;
    }
    if (rows.any((r) => r.added != null)) {
      rows.sort((a, b) => (b.added ?? 0).compareTo(a.added ?? 0));
    }
    final all = rows.map(AppMediaRepository.mediaFromStream).toList();
    _rememberAll(all);
    return all;
  }

  /// Kids words or a Kids panel name: the same test as LG (`isKidsCategory`
  /// in platforms/lg-tv-web/src/core/names.ts).
  static bool _isKidsCategoryName(String name) =>
      KidsPanelCategories.looksKids(name) ||
      KidsPanelCategories.allNames
          .any((n) => KidsPanelCategories.matches(n, name));

  /// Coming Soon (client 2 Nov #3): only titles the provider marks as not
  /// released yet (backend `sort=upcoming`, App-Backend #81), movies
  /// then series. Empty (row hidden) when there are none or on error.
  @override
  Future<List<MediaItem>> getComingSoon() async {
    Future<List<CatalogStreamDto>> load(
      Future<PageResult<CatalogStreamDto>> Function() call,
    ) async {
      try {
        return (await call()).items;
      } catch (_) {
        return const [];
      }
    }

    final r = await Future.wait([
      load(() => _media.vodStreams(limit: 10, sort: 'upcoming')),
      load(() => _media.seriesList(limit: 10, sort: 'upcoming')),
    ]);
    final items = [
      for (final s in r[0]) AppMediaRepository.mediaFromStream(s, upcoming: true),
      for (final s in r[1]) AppMediaRepository.mediaFromStream(s, upcoming: true),
    ];
    _rememberAll(items);
    return items;
  }
}
