import 'package:domain/domain.dart';
import 'package:flutter/foundation.dart' show compute;

import '../../diag/diag.dart';
import '../provider_adapter.dart';
import '../provider_http.dart';
import '../provider_models.dart';
import 'm3u_parser.dart';

/// M3U / M3U8 playlists (URL). The whole playlist is one download, so it is
/// fetched once, parsed + grouped off the UI thread, and every list/detail
/// call is answered from that copy. Notes: docs/PROVIDER_PROTOCOLS.md §2.
///
/// Series come from episode entries ("Show S01E02" or `/series/` URLs),
/// grouped by playlist group + show name. The full XMLTV guide (`url-tvg`)
/// is read by the EPG sync in Phase 6; [shortEpg] returns nothing here.
class M3uAdapter implements ProviderAdapter {
  M3uAdapter(this.credentials, {ProviderHttp? http}) : _http = http ?? ProviderHttp() {
    final u = credentials.playlistUri;
    if (u == null) throw const ProviderFailure(ProviderFailureKind.invalidInput, 'url');
    _uri = u;
  }

  static void register({ProviderLimits limits = const ProviderLimits()}) {
    ProviderAdapterFactory.register(
      ProviderKind.m3u,
      (c) => M3uAdapter(c as M3uCredentials, http: ProviderHttp(limits: limits)),
    );
  }

  final M3uCredentials credentials;
  final ProviderHttp _http;
  late final Uri _uri;
  M3uCatalog? _catalog;
  Future<M3uCatalog>? _loading;

  /// EPG URLs from the playlist header (+ the one the user typed).
  List<String> get epgUrls => [
        if ((credentials.epgUrl ?? '').trim().isNotEmpty) credentials.epgUrl!.trim(),
        ...?_catalog?.epgUrls,
      ];

  @override
  ProviderKind get kind => ProviderKind.m3u;

  @override
  ProviderCapabilities get capabilities => ProviderCapabilities(
        live: true,
        movies: _catalog?.movies.isNotEmpty ?? true,
        series: _catalog?.series.isNotEmpty ?? true,
        epg: false, // XMLTV sync in Phase 6
      );

  /// Downloads + parses the playlist (always fresh: spec §3.5).
  @override
  Future<ProviderAccount> authenticate() async {
    _catalog = null;
    _loading = null;
    final c = await _load();
    if (c.isEmpty) {
      throw ProviderFailure(
        ProviderFailureKind.badResponse,
        c.hadHeader ? 'empty playlist' : 'not a playlist',
      );
    }
    return const ProviderAccount(status: ConnectionStatus.active);
  }

  Future<M3uCatalog> _load() {
    final ready = _catalog;
    if (ready != null) return Future.value(ready);
    return _loading ??= () async {
      try {
        final text = await _http.getText(_uri);
        final sw = Stopwatch()..start();
        final c = text.length >= _http.limits.isolateDecodeBytes
            ? await compute(buildM3uCatalog, text)
            : buildM3uCatalog(text);
        Diag.panel('m3u parsed in ${sw.elapsedMilliseconds}ms: header #EXTM3U ${c.hadHeader ? 'yes' : 'NO'}, '
            'live ${c.channels.length}, movies ${c.movies.length}, series ${c.series.length}, '
            'groups ${c.liveCategories.length}/${c.movieCategories.length}/${c.seriesCategories.length}, epg urls ${c.epgUrls.length}');
        _catalog = c;
        return c;
      } finally {
        _loading = null;
      }
    }();
  }

  @override
  Future<List<ProviderCategory>> liveCategories() async => (await _load()).liveCategories;

  @override
  Future<List<ProviderChannel>> liveChannels({String? categoryId}) async =>
      _filter((await _load()).channels, categoryId, (c) => c.categoryId);

  @override
  Future<List<ProviderCategory>> movieCategories() async => (await _load()).movieCategories;

  @override
  Future<List<ProviderMovie>> movies({String? categoryId}) async =>
      _filter((await _load()).movies, categoryId, (m) => m.categoryId);

  @override
  Future<List<ProviderCategory>> seriesCategories() async => (await _load()).seriesCategories;

  @override
  Future<List<ProviderSeries>> series({String? categoryId}) async =>
      _filter((await _load()).series, categoryId, (s) => s.categoryId);

  @override
  Future<ProviderMovieDetails> movieDetails(String movieId) async {
    final c = await _load();
    final m = c.movies.where((m) => m.id == movieId).firstOrNull;
    if (m == null) throw const ProviderFailure(ProviderFailureKind.badResponse, 'movie not in playlist');
    return ProviderMovieDetails(movie: m);
  }

  @override
  Future<ProviderSeriesDetails> seriesDetails(String seriesId) async {
    final c = await _load();
    final s = c.series.where((s) => s.id == seriesId).firstOrNull;
    if (s == null) throw const ProviderFailure(ProviderFailureKind.badResponse, 'series not in playlist');
    return ProviderSeriesDetails(series: s, episodes: c.episodes[seriesId] ?? const {});
  }

  @override
  Future<List<EpgEntry>> shortEpg(ProviderChannel channel, {int limit = 4}) async => const [];

  /// The playlist URL itself, with the entry's own headers (User-Agent …).
  @override
  Future<ResolvedStream> resolveStream(StreamRef ref) async {
    final url = ref.command == null ? null : Uri.tryParse(ref.command!);
    if (url == null) throw const ProviderFailure(ProviderFailureKind.badResponse, 'no stream url');
    final c = _catalog;
    return ResolvedStream(url: url, headers: c?.headers['${ref.kind.name}:${ref.id}'] ?? const {});
  }

  @override
  void dispose() => _http.close();

  static List<T> _filter<T>(List<T> all, String? categoryId, String? Function(T) cat) =>
      (categoryId == null || categoryId.isEmpty) ? all : all.where((x) => cat(x) == categoryId).toList();
}

/// Everything a playlist offers, already grouped. Built in an isolate.
class M3uCatalog {
  const M3uCatalog({
    required this.channels,
    required this.movies,
    required this.series,
    required this.episodes,
    required this.liveCategories,
    required this.movieCategories,
    required this.seriesCategories,
    required this.headers,
    required this.epgUrls,
    required this.hadHeader,
  });

  final List<ProviderChannel> channels;
  final List<ProviderMovie> movies;
  final List<ProviderSeries> series;

  /// series id → season → episodes.
  final Map<String, Map<int, List<ProviderEpisode>>> episodes;
  final List<ProviderCategory> liveCategories;
  final List<ProviderCategory> movieCategories;
  final List<ProviderCategory> seriesCategories;

  /// "kind:id" → request headers for that stream.
  final Map<String, Map<String, String>> headers;
  final List<String> epgUrls;
  final bool hadHeader;

  bool get isEmpty => channels.isEmpty && movies.isEmpty && series.isEmpty;
}

/// Playlist text → grouped catalog. Top-level so it can run in an isolate.
M3uCatalog buildM3uCatalog(String text) {
  final p = parseM3u(text);
  final channels = <ProviderChannel>[];
  final movies = <ProviderMovie>[];
  final seriesById = <String, ProviderSeries>{};
  final episodes = <String, Map<int, List<ProviderEpisode>>>{};
  final headers = <String, Map<String, String>>{};
  final liveCats = <String>{}, movieCats = <String>{}, seriesCats = <String>{};
  final liveSeen = <String>{};

  for (final e in p.entries) {
    final kind = m3uKindOf(e);
    final id = m3uEntryId(e);
    final ext = _extOf(e.url);
    if (e.headers.isNotEmpty) headers['${kind.name}:$id'] = e.headers;

    switch (kind) {
      case MediaKind.live:
      case MediaKind.sports:
        if (isProviderAdOrHeaderChannel(e.title)) continue;
        // Same channel listed twice under another URL: keep the first.
        final dupKey = '${e.attr('tvg-id') ?? ''}|${e.title.toLowerCase()}';
        if (e.attr('tvg-id') != null && !liveSeen.add(dupKey)) continue;
        if (e.group != null) liveCats.add(e.group!);
        channels.add(ProviderChannel(
          id: id,
          name: e.title,
          stream: StreamRef(kind: MediaKind.live, id: id, command: e.url),
          number: int.tryParse(e.attr('tvg-chno') ?? ''),
          logoUrl: e.attr('tvg-logo'),
          categoryId: e.group,
          epgId: e.attr('tvg-id'),
          catchupDays: int.tryParse(e.attr('catchup-days') ?? e.attr('timeshift') ?? '') ?? 0,
        ));
      case MediaKind.movie:
        if (e.group != null) movieCats.add(e.group!);
        movies.add(ProviderMovie(
          id: id,
          name: e.title,
          stream: StreamRef(kind: MediaKind.movie, id: id, extension: ext, command: e.url),
          posterUrl: e.attr('tvg-logo'),
          year: _yearInName(e.title),
          categoryId: e.group,
        ));
      case MediaKind.series:
        final info = m3uEpisodeInfo(e.title);
        final show = info?.show ?? e.title;
        final seriesId = m3uStableId('${e.group ?? ''}|${show.toLowerCase()}');
        if (e.group != null) seriesCats.add(e.group!);
        seriesById.putIfAbsent(
          seriesId,
          () => ProviderSeries(
            id: seriesId,
            name: show,
            posterUrl: e.attr('tvg-logo'),
            year: _yearInName(show),
            categoryId: e.group,
          ),
        );
        final season = info?.season ?? 1;
        final list = episodes.putIfAbsent(seriesId, () => {}).putIfAbsent(season, () => []);
        list.add(ProviderEpisode(
          id: id,
          seriesId: seriesId,
          season: season,
          number: info?.episode ?? list.length + 1,
          title: e.title,
          stream: StreamRef(kind: MediaKind.series, id: id, extension: ext, command: e.url),
          durationSec: e.duration > 0 ? e.duration : null,
        ));
    }
  }
  for (final seasons in episodes.values) {
    for (final l in seasons.values) {
      l.sort((a, b) => a.number.compareTo(b.number));
    }
  }
  List<ProviderCategory> cats(Set<String> names) =>
      [for (final n in names) ProviderCategory(id: n, name: n)];
  return M3uCatalog(
    channels: channels,
    movies: movies,
    series: seriesById.values.toList(),
    episodes: episodes,
    liveCategories: cats(liveCats),
    movieCategories: cats(movieCats),
    seriesCategories: cats(seriesCats),
    headers: headers,
    epgUrls: p.epgUrls,
    hadHeader: p.hadHeader,
  );
}

String? _extOf(String url) {
  final path = Uri.tryParse(url)?.path ?? '';
  final m = RegExp(r'\.([A-Za-z0-9]{2,5})$').firstMatch(path);
  return m?.group(1)?.toLowerCase();
}

int? _yearInName(String name) {
  final m = RegExp(r'\((19|20)\d{2}\)').firstMatch(name);
  return m == null ? null : int.parse(m.group(0)!.substring(1, 5));
}
