import 'package:domain/domain.dart';

/// One openly licensed asset shown in demo mode, with its credit line.
class DemoCredit {
  const DemoCredit({
    required this.title,
    required this.author,
    required this.licence,
    required this.licenceUrl,
    required this.source,
  });

  final String title;
  final String author;
  final String licence;
  final String licenceUrl;
  final String source;

  /// Line shown on the details screen, e.g. "© Blender Foundation · CC BY 3.0".
  String get creditLine => '© $author · $licence';
}

// Google's gtv-videos-bucket now answers 403 (client 2 Nov: "demo mode does
// not work"), so posters come from Wikimedia Commons and films from Blender /
// public HLS test hosts. All checked reachable on 3 Nov 2026.
const _wm = 'https://upload.wikimedia.org/wikipedia/commons';
const _bbbPoster = '$_wm/c/c5/Big_buck_bunny_poster_big.jpg';
const _edPoster = '$_wm/0/0c/ElephantsDreamPoster.jpg';
const _sintelPoster = '$_wm/8/8f/Sintel_poster.jpg';
const _tosPoster = '$_wm/7/70/Tos-poster.png';

/// Store-review demo content. Only openly licensed films (Blender Foundation
/// open movies, Creative Commons Attribution) and public HLS test streams,
/// so the demo never contacts a provider host or shows third-party catalogue.
class DemoContent {
  DemoContent._();

  static const credits = <String, DemoCredit>{
    'demo-bbb': DemoCredit(
      title: 'Big Buck Bunny (2008)',
      author: 'Blender Foundation',
      licence: 'CC BY 3.0',
      licenceUrl: 'https://creativecommons.org/licenses/by/3.0/',
      source: 'https://peach.blender.org',
    ),
    'demo-ed': DemoCredit(
      title: 'Elephants Dream (2006)',
      author: 'Blender Foundation',
      licence: 'CC BY 2.5',
      licenceUrl: 'https://creativecommons.org/licenses/by/2.5/',
      source: 'https://orange.blender.org',
    ),
    'demo-sintel': DemoCredit(
      title: 'Sintel (2010)',
      author: 'Blender Foundation',
      licence: 'CC BY 3.0',
      licenceUrl: 'https://creativecommons.org/licenses/by/3.0/',
      source: 'https://durian.blender.org',
    ),
    'demo-tos': DemoCredit(
      title: 'Tears of Steel (2012)',
      author: 'Blender Foundation',
      licence: 'CC BY 3.0',
      licenceUrl: 'https://creativecommons.org/licenses/by/3.0/',
      source: 'https://mango.blender.org (file: download.blender.org)',
    ),
    'demo-live-1': DemoCredit(
      title: 'Demo Channel 1 (Big Buck Bunny HLS)',
      author: 'Blender Foundation',
      licence: 'CC BY 3.0',
      licenceUrl: 'https://creativecommons.org/licenses/by/3.0/',
      source: 'https://test-streams.mux.dev (public HLS test stream)',
    ),
    'demo-live-2': DemoCredit(
      title: 'Demo Channel 2 (HLS test pattern)',
      author: 'Apple Inc.',
      licence: 'Public HLS example stream for testing',
      licenceUrl:
          'https://developer.apple.com/streaming/examples/',
      source: 'https://developer.apple.com/streaming/examples/',
    ),
  };

  static const movies = <MediaItem>[
    MediaItem(
      id: 'demo-bbb',
      title: 'Big Buck Bunny',
      kind: MediaKind.movie,
      year: 2008,
      rating: 7.6,
      durationLabel: '10 min',
      genres: ['Animation', 'Comedy'],
      badges: ['DEMO', 'HD'],
      synopsis:
          'A giant rabbit takes on three bullying rodents in this open '
          'movie by the Blender Foundation.',
      posterUrl: _bbbPoster,
      backdropUrl: _bbbPoster,
      streamUrl: 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
      containerExtension: 'm3u8',
      categoryId: 'demo-kids',
    ),
    MediaItem(
      id: 'demo-ed',
      title: 'Elephants Dream',
      kind: MediaKind.movie,
      year: 2006,
      rating: 6.5,
      durationLabel: '11 min',
      genres: ['Animation', 'Sci-Fi'],
      badges: ['DEMO', 'HD'],
      synopsis:
          'Two characters explore a strange mechanical world. The first '
          'Blender open movie.',
      posterUrl: _edPoster,
      backdropUrl: _edPoster,
      streamUrl:
          'https://download.blender.org/ED/elephantsdream-720-h264-st-aac.mov',
      containerExtension: 'mov',
      categoryId: 'demo-fantasy',
    ),
    MediaItem(
      id: 'demo-sintel',
      title: 'Sintel (trailer)',
      kind: MediaKind.movie,
      year: 2010,
      rating: 7.4,
      durationLabel: '1 min',
      genres: ['Animation', 'Fantasy'],
      badges: ['DEMO', 'HD'],
      synopsis:
          'A lonely young woman searches for the baby dragon she once '
          'rescued.',
      posterUrl: _sintelPoster,
      backdropUrl: _sintelPoster,
      // Trailer: the full film is no longer on a direct public link.
      streamUrl:
          'https://download.blender.org/durian/trailer/sintel_trailer-720p.mp4',
      containerExtension: 'mp4',
      categoryId: 'demo-fantasy',
    ),
    MediaItem(
      id: 'demo-tos',
      title: 'Tears of Steel',
      kind: MediaKind.movie,
      year: 2012,
      rating: 6.2,
      durationLabel: '12 min',
      genres: ['Sci-Fi', 'Action'],
      badges: ['DEMO', 'HD'],
      synopsis:
          'Scientists in a future Amsterdam try to save the world from '
          'robots.',
      posterUrl: _tosPoster,
      backdropUrl: _tosPoster,
      // From the Blender Foundation's own server (client 6 Nov #7: no third-party
      // test servers); 720p QuickTime / H.264.
      streamUrl:
          'https://download.blender.org/demo/movies/ToS/tears_of_steel_720p.mov',
      containerExtension: 'mov',
      categoryId: 'demo-fantasy',
    ),
  ];

  static const series = <MediaItem>[
    MediaItem(
      id: 'demo-series-open-movies',
      title: 'Blender Open Movies (demo series)',
      kind: MediaKind.series,
      year: 2012,
      rating: 7.0,
      genres: ['Animation'],
      badges: ['DEMO'],
      synopsis:
          'Demo series to try seasons and episodes: each episode is one of the '
          'Blender Foundation open movies (CC BY).',
      posterUrl: _sintelPoster,
      backdropUrl: _sintelPoster,
      categoryId: 'demo-series',
    ),
  ];

  static final episodes = <Episode>[
    for (var i = 0; i < movies.length; i++)
      Episode(
        id: 'demo-ep-${i + 1}',
        seriesId: 'demo-series-open-movies',
        season: 1,
        number: i + 1,
        title: movies[i].title,
        durationLabel: movies[i].durationLabel ?? '',
        synopsis: movies[i].synopsis,
        stillUrl: movies[i].backdropUrl,
        streamUrl: movies[i].streamUrl,
        containerExtension: movies[i].containerExtension ?? 'mp4',
      ),
  ];

  static const live = <LiveChannel>[
    LiveChannel(
      id: 'demo-live-1',
      name: 'Demo Channel 1',
      code: 'D1',
      nowTitle: 'Big Buck Bunny',
      nextTitle: 'Big Buck Bunny',
      badge: 'DEMO',
      specs: ['HD'],
      imageUrl: _bbbPoster,
      streamUrl: 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
    ),
    LiveChannel(
      id: 'demo-live-2',
      name: 'Demo Channel 2',
      code: 'D2',
      nowTitle: 'HLS test pattern',
      nextTitle: 'HLS test pattern',
      badge: 'DEMO',
      specs: ['HD'],
      streamUrl:
          'https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8',
      accent: LiveAccent.magenta,
    ),
  ];

  /// Live channels as catalog rows (what the real Live TV tab, search and
  /// player channel list browse), in the one demo package.
  static final liveItems = <MediaItem>[
    for (final c in live)
      MediaItem(
        id: c.id,
        title: c.name,
        kind: MediaKind.live,
        isLive: true,
        badges: [if (c.badge != null) c.badge!, ...c.specs],
        posterUrl: c.imageUrl,
        backdropUrl: c.imageUrl,
        streamUrl: c.streamUrl,
        containerExtension: 'm3u8',
        categoryId: 'demo-live',
      ),
  ];

  /// True for an https URL on one of [hosts]; the demo opens nothing else.
  static bool isAllowedUrl(String? url) {
    final u = Uri.tryParse(url ?? '');
    return u != null && u.scheme == 'https' && hosts.contains(u.host);
  }

  /// Every network host the demo may contact (posters + streams).
  static Set<String> get hosts => {
    for (final m in [...movies, ...series]) ...[
      if (m.posterUrl != null) Uri.parse(m.posterUrl!).host,
      if (m.streamUrl != null) Uri.parse(m.streamUrl!).host,
    ],
    for (final c in live) ...[
      if (c.imageUrl != null) Uri.parse(c.imageUrl!).host,
      if (c.streamUrl != null) Uri.parse(c.streamUrl!).host,
    ],
  };
}

/// [CatalogRepository] over [DemoContent] only. No network calls of its own.
class DemoCatalogRepository implements CatalogRepository {
  DemoCatalogRepository();

  final List<MediaItem> _myList = [];

  List<MediaItem> get _all => [...DemoContent.movies, ...DemoContent.series];

  MediaItem? _find(String id) {
    for (final m in [..._all, ...DemoContent.liveItems]) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// Local My List for the demo (kept in memory only).
  bool inMyList(String id) => _myList.any((m) => m.id == id);

  void toggleMyList(MediaItem item) {
    if (inMyList(item.id)) {
      _myList.removeWhere((m) => m.id == item.id);
    } else {
      _myList.add(item);
    }
  }

  @override
  Future<HomeFeed> getHomeFeed() async => HomeFeed(
    hero: DemoContent.movies[2],
    matches: const [],
    continueWatching: const [],
    top10: DemoContent.movies,
    arabicOriginals: DemoContent.series,
    liveChannels: DemoContent.live,
  );

  @override
  Future<List<MediaItem>> getMovies() async => DemoContent.movies;

  @override
  Future<List<MediaItem>> getSeries() async => DemoContent.series;

  @override
  Future<List<LiveChannel>> getLiveChannels() async => DemoContent.live;

  @override
  Future<List<SportsMatch>> getSportsMatches() async => const [];

  @override
  Future<CatalogPage<SportsMatch>> browseSports({
    String? cursor,
    int limit = 10,
  }) async => const CatalogPage(items: []);

  @override
  Future<List<SportsMatch>> searchSports(String query) async => const [];

  @override
  Future<List<MediaItem>> getMyList() async => List.unmodifiable(_myList);

  @override
  Future<List<MediaItem>> search(String query, {MediaKind? kind}) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return [
      for (final m in [..._all, ...DemoContent.liveItems])
        if ((kind == null || m.kind == kind) &&
            (m.title.toLowerCase().contains(q) ||
                m.genres.any((g) => g.toLowerCase().contains(q))))
          m,
    ];
  }

  @override
  Future<CatalogPage<MediaItem>> searchPage(
    String query, {
    MediaKind? kind,
    String? cursor,
    int limit = 40,
    String? categoryId,
  }) async {
    final r = await search(query, kind: kind);
    return CatalogPage(
      items: [
        for (final m in r)
          if (categoryId == null || m.categoryId == categoryId) m,
      ],
    );
  }

  @override
  Future<MediaItem?> getById(String id, {MediaKind? kind}) async => _find(id);

  @override
  String? knownContainerExtension(String streamId) => 'mp4';

  @override
  String? knownSeriesIdForEpisode(String episodeId) =>
      episodeId.startsWith('demo-ep-') ? 'demo-series-open-movies' : null;

  @override
  Future<List<CatalogCategory>> getCategories(MediaKind kind) async =>
      switch (kind) {
        MediaKind.movie => const [
          // A Kids sample (client 6 Nov #8: the demo Kids section was empty).
          CatalogCategory(id: 'demo-kids', name: 'Kids & Family'),
          CatalogCategory(id: 'demo-fantasy', name: 'Fantasy & Sci-Fi'),
        ],
        MediaKind.series => const [
          CatalogCategory(id: 'demo-series', name: 'Open Movies'),
        ],
        MediaKind.live => const [
          CatalogCategory(id: 'demo-live', name: 'Demo Channels'),
        ],
        MediaKind.sports => const [],
      };

  @override
  Future<CatalogPage<MediaItem>> browse({
    required MediaKind kind,
    String? categoryId,
    String? cursor,
    int limit = 10,
  }) async {
    final pool = kind == MediaKind.series
        ? DemoContent.series
        : kind == MediaKind.movie
        ? DemoContent.movies
        : kind == MediaKind.live
        ? DemoContent.liveItems
        : const <MediaItem>[];
    return CatalogPage(
      items: [
        for (final m in pool)
          if (categoryId == null || m.categoryId == categoryId) m,
      ],
    );
  }

  @override
  Future<List<String>> getGenres() async => {
    for (final m in _all) ...m.genres,
  }.toList();

  @override
  Future<List<MediaItem>> getByGenre(String genre) async => [
    for (final m in _all)
      if (m.genres.contains(genre)) m,
  ];

  @override
  Future<List<Episode>> getEpisodes(String seriesId, {int season = 1}) async =>
      seriesId == 'demo-series-open-movies' && season == 1
      ? DemoContent.episodes
      : const [];

  @override
  Future<int> getSeasonCount(String seriesId) async =>
      seriesId == 'demo-series-open-movies' ? 1 : 0;

  @override
  Future<List<int>> getSeasonNumbers(String seriesId) async =>
      seriesId == 'demo-series-open-movies' ? const [1] : const [];

  @override
  Future<List<MediaItem>> getRelated(String id) async => [
    for (final m in DemoContent.movies)
      if (m.id != id) m,
  ];

  @override
  Future<List<MediaItem>> getTrending() async => DemoContent.movies;

  @override
  Future<List<MediaItem>> getNewReleases() async =>
      [...DemoContent.movies]..sort((a, b) => (b.year ?? 0) - (a.year ?? 0));

  @override
  Future<List<MediaItem>> getNewSeries() async => DemoContent.series;

  @override
  Future<List<MediaItem>> getComingSoon() async => const [];
}
