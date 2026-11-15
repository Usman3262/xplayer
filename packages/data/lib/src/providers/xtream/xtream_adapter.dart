import 'dart:convert';

import 'package:domain/domain.dart';

import '../../backend/json_util.dart';
import '../../diag/diag.dart';
import '../../remote/json_read.dart';
import '../provider_adapter.dart';
import '../provider_http.dart';
import '../provider_models.dart';

/// Xtream Codes panels (Neo is one). Notes: docs/PROVIDER_PROTOCOLS.md §1.
/// Parsing is tolerant: ids/numbers arrive as int or string, fields go missing,
/// dates look like "2023-07-06 (country)", seasons may only exist as episode
/// groups. Credentials only ever appear in request URLs, never in logs/errors.
class XtreamAdapter implements ProviderAdapter {
  XtreamAdapter(
    this.credentials, {
    ProviderHttp? http,
    this.preferredLiveFormat = 'ts',
    DateTime Function()? clock,
  })  : _http = http ?? ProviderHttp(),
        _clock = clock ?? DateTime.now {
    final base = credentials.baseUri;
    if (base == null) {
      throw const ProviderFailure(ProviderFailureKind.invalidInput, 'server');
    }
    _base = base;
  }

  /// Registers Xtream in [ProviderAdapterFactory]. [liveFormat] comes from the
  /// admin setting `player.live_format` (ts | m3u8).
  static void register({ProviderLimits limits = const ProviderLimits(), String liveFormat = 'ts'}) {
    ProviderAdapterFactory.register(
      ProviderKind.xtream,
      (c) => XtreamAdapter(
        c as XtreamCredentials,
        http: ProviderHttp(limits: limits),
        preferredLiveFormat: liveFormat,
      ),
    );
  }

  final XtreamCredentials credentials;
  final String preferredLiveFormat;
  final ProviderHttp _http;
  final DateTime Function() _clock;
  late final Uri _base;

  /// From the last login; decides the live container (ts / m3u8).
  List<String> _allowedFormats = const [];

  @override
  ProviderKind get kind => ProviderKind.xtream;

  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities(
        live: true,
        movies: true,
        series: true,
        epg: true,
        catchup: true,
        incrementalByAdded: true,
      );

  Uri _api([Map<String, String> extra = const {}]) => _base.replace(
        path: '${_base.path}/player_api.php',
        queryParameters: {
          'username': credentials.username.trim(),
          'password': credentials.password,
          ...extra,
        },
      );

  Future<Object?> _action(String action, [Map<String, String> extra = const {}]) =>
      _http.getJson(_api({'action': action, ...extra}));

  // ── Account ──────────────────────────────────────────────────────────────

  @override
  Future<ProviderAccount> authenticate() async {
    final raw = await _http.getJson(_api(), auth: true);
    final ProviderAccount account;
    try {
      account = parseAccount(raw, now: _clock());
    } on ProviderFailure catch (f) {
      final ui = jsonMap(jsonMap(raw)['user_info']);
      Diag.panel('xtream login refused (${f.kind.name}): reply ${raw.runtimeType}, '
          'keys ${jsonMap(raw).keys.toList()}, auth=${ui['auth']}, status=${ui['status']}, exp_date=${ui['exp_date']}');
      rethrow;
    }
    _allowedFormats = account.allowedOutputFormats;
    return account;
  }

  /// Login reply → account, or throws [ProviderFailure] (unauthorized /
  /// expired / banned). Wrong passwords often come back as `[]`, `{}` or
  /// `user_info.auth = 0` with HTTP 200.
  static ProviderAccount parseAccount(Object? raw, {required DateTime now}) {
    final root = jsonMap(raw);
    final ui = jsonMap(root['user_info']);
    if (ui.isEmpty || jsonInt(ui['auth']) != 1) {
      throw const ProviderFailure(ProviderFailureKind.unauthorized, 'auth=0');
    }
    final status = (jsonStr(ui['status']) ?? '').trim().toLowerCase();
    final expSec = jsonInt(ui['exp_date']);
    final expires = (expSec == null || expSec <= 0)
        ? null
        : DateTime.fromMillisecondsSinceEpoch(expSec * 1000, isUtc: true);
    if (status == 'expired' || (expires != null && expires.isBefore(now))) {
      throw const ProviderFailure(ProviderFailureKind.expired, 'expired');
    }
    if (status == 'banned' || status == 'disabled') {
      throw ProviderFailure(ProviderFailureKind.banned, status);
    }
    final si = jsonMap(root['server_info']);
    return ProviderAccount(
      status: ConnectionStatus.active,
      expiresAt: expires,
      isTrial: jsonBool(ui['is_trial']) ?? false,
      maxConnections: jsonInt(ui['max_connections']),
      activeConnections: jsonInt(ui['active_cons']),
      allowedOutputFormats: jsonStrList(ui['allowed_output_formats'])
          .map((f) => f.trim().toLowerCase())
          .where((f) => f.isNotEmpty)
          .toList(),
      serverTimezone: jsonStr(si['timezone']),
    );
  }

  // ── Categories & lists ───────────────────────────────────────────────────

  @override
  Future<List<ProviderCategory>> liveCategories() async =>
      parseCategories(await _action('get_live_categories'));

  @override
  Future<List<ProviderCategory>> movieCategories() async =>
      parseCategories(await _action('get_vod_categories'));

  @override
  Future<List<ProviderCategory>> seriesCategories() async =>
      parseCategories(await _action('get_series_categories'));

  static List<ProviderCategory> parseCategories(Object? raw) => [
        for (final c in _list(raw))
          if (_id(c['category_id']) case final id?)
            ProviderCategory(
              id: id,
              name: (jsonStr(c['category_name']) ?? '').trim(),
              parentId: _id(c['parent_id']) == '0' ? null : _id(c['parent_id']),
            ),
      ];

  Map<String, String> _cat(String? categoryId) =>
      categoryId == null || categoryId.isEmpty ? const {} : {'category_id': categoryId};

  @override
  Future<List<ProviderChannel>> liveChannels({String? categoryId}) async =>
      parseLiveStreams(await _action('get_live_streams', _cat(categoryId)));

  static List<ProviderChannel> parseLiveStreams(Object? raw) => [
        for (final s in _list(raw))
          if (_id(s['stream_id']) case final id?)
            if (!isProviderAdOrHeaderChannel(jsonStr(s['name']) ?? ''))
              ProviderChannel(
                id: id,
                name: (jsonStr(s['name']) ?? '').trim(),
                stream: StreamRef(kind: MediaKind.live, id: id),
                number: jsonInt(s['num']),
                logoUrl: _nonEmpty(s['stream_icon']),
                categoryId: _id(s['category_id']),
                epgId: _nonEmpty(s['epg_channel_id']),
                catchupDays: (jsonBool(s['tv_archive']) ?? false) ? (jsonInt(s['tv_archive_duration']) ?? 0) : 0,
                addedSec: jsonInt(s['added']),
              ),
      ];

  @override
  Future<List<ProviderMovie>> movies({String? categoryId}) async =>
      parseVodStreams(await _action('get_vod_streams', _cat(categoryId)));

  static List<ProviderMovie> parseVodStreams(Object? raw) => [
        for (final s in _list(raw))
          if (_id(s['stream_id']) case final id?) _movie(s, id),
      ];

  static ProviderMovie _movie(Map<String, dynamic> s, String id) {
    final name = (jsonStr(s['name']) ?? '').trim();
    return ProviderMovie(
      id: id,
      name: name,
      stream: StreamRef(kind: MediaKind.movie, id: id, extension: _ext(s['container_extension'])),
      posterUrl: _nonEmpty(s['stream_icon']) ?? _nonEmpty(s['cover']),
      rating: jsonDouble(s['rating']),
      year: _year(s['year']) ?? _year(s['releasedate']) ?? _yearInName(name),
      categoryId: _id(s['category_id']),
      addedSec: jsonInt(s['added']),
      tmdbId: _tmdb(s['tmdb'] ?? s['tmdb_id']),
    );
  }

  @override
  Future<List<ProviderSeries>> series({String? categoryId}) async =>
      parseSeries(await _action('get_series', _cat(categoryId)));

  static List<ProviderSeries> parseSeries(Object? raw) => [
        for (final s in _list(raw))
          if (_id(s['series_id']) case final id?) _series(s, id),
      ];

  static ProviderSeries _series(Map<String, dynamic> s, String id) {
    final name = (jsonStr(s['name']) ?? '').trim();
    return ProviderSeries(
      id: id,
      name: name,
      posterUrl: _nonEmpty(s['cover']),
      backdropUrl: _firstUrl(s['backdrop_path']),
      plot: _nonEmpty(s['plot']),
      genres: _genres(s['genre']),
      rating: jsonDouble(s['rating']),
      year: _year(s['releaseDate']) ?? _year(s['release_date']) ?? _yearInName(name),
      categoryId: _id(s['category_id']),
      addedSec: jsonInt(s['last_modified']),
      tmdbId: _tmdb(s['tmdb'] ?? s['tmdb_id']),
    );
  }

  // ── Details ──────────────────────────────────────────────────────────────

  @override
  Future<ProviderMovieDetails> movieDetails(String movieId) async =>
      parseVodInfo(await _action('get_vod_info', {'vod_id': movieId}), movieId);

  static ProviderMovieDetails parseVodInfo(Object? raw, String movieId) {
    final root = jsonMap(raw);
    final info = jsonMap(root['info']);
    final data = jsonMap(root['movie_data']);
    if (info.isEmpty && data.isEmpty) {
      throw const ProviderFailure(ProviderFailureKind.badResponse, 'vod_info empty');
    }
    final id = _id(data['stream_id']) ?? movieId;
    final merged = <String, dynamic>{
      ...info,
      ...data,
      'stream_icon': info['movie_image'] ?? info['cover_big'] ?? data['stream_icon'],
      'releasedate': info['releasedate'] ?? info['release_date'],
      'tmdb': info['tmdb_id'],
      // Some panels only name the movie in movie_data.
      'name': _nonEmpty(data['name']) ?? _nonEmpty(info['name']) ?? _nonEmpty(info['o_name']),
    };
    return ProviderMovieDetails(
      movie: _movie(merged, id),
      plot: _nonEmpty(info['plot']) ?? _nonEmpty(info['description']),
      genres: _genres(info['genre']),
      cast: _nonEmpty(info['cast']) ?? _nonEmpty(info['actors']),
      director: _nonEmpty(info['director']),
      durationSec: jsonInt(info['duration_secs']) ?? parseDurationToSeconds(info['duration']),
      backdropUrl: _firstUrl(info['backdrop_path']),
      trailerYoutubeId: _nonEmpty(info['youtube_trailer']),
    );
  }

  @override
  Future<ProviderSeriesDetails> seriesDetails(String seriesId) async =>
      parseSeriesInfo(await _action('get_series_info', {'series_id': seriesId}), seriesId);

  static ProviderSeriesDetails parseSeriesInfo(Object? raw, String seriesId) {
    final root = jsonMap(raw);
    final info = jsonMap(root['info']);
    if (info.isEmpty && root['episodes'] == null) {
      throw const ProviderFailure(ProviderFailureKind.badResponse, 'series_info empty');
    }
    final episodes = <int, List<ProviderEpisode>>{};
    void add(Map<String, dynamic> e, int? groupSeason) {
      final id = _id(e['id']);
      if (id == null) return;
      final season = jsonInt(e['season']) ?? groupSeason ?? 1;
      final ei = jsonMap(e['info']);
      final number = jsonInt(e['episode_num']) ?? (episodes[season]?.length ?? 0) + 1;
      episodes.putIfAbsent(season, () => []).add(ProviderEpisode(
            id: id,
            seriesId: seriesId,
            season: season,
            number: number,
            title: (jsonStr(e['title']) ?? '').trim(), // empty → the app labels "Episode n"
            stream: StreamRef(kind: MediaKind.series, id: id, extension: _ext(e['container_extension'])),
            durationSec: jsonInt(ei['duration_secs']) ?? parseDurationToSeconds(ei['duration']),
            plot: _nonEmpty(ei['plot']),
            stillUrl: _nonEmpty(ei['movie_image']) ?? _nonEmpty(ei['cover_big']),
          ));
    }

    final rawEps = root['episodes'];
    if (rawEps is Map) {
      rawEps.forEach((k, v) {
        for (final e in _list(v)) {
          add(e, int.tryParse('$k'));
        }
      });
    } else {
      // Some panels send one flat list with a `season` field.
      for (final e in _list(rawEps)) {
        add(e, null);
      }
    }
    for (final list in episodes.values) {
      list.sort((a, b) => a.number.compareTo(b.number));
    }
    final s = _series({...info, 'tmdb': info['tmdb'] ?? info['tmdb_id']}, seriesId);
    return ProviderSeriesDetails(series: s, episodes: episodes);
  }

  // ── EPG ──────────────────────────────────────────────────────────────────

  @override
  Future<List<EpgEntry>> shortEpg(ProviderChannel channel, {int limit = 4}) async =>
      parseShortEpg(await _action('get_short_epg', {'stream_id': channel.id, 'limit': '$limit'}));

  static List<EpgEntry> parseShortEpg(Object? raw) {
    final out = <EpgEntry>[];
    for (final e in _list(jsonMap(raw)['epg_listings'])) {
      final start = _unix(e['start_timestamp']) ?? _parseTime(e['start']);
      final end = _unix(e['stop_timestamp']) ?? _parseTime(e['end'] ?? e['stop']);
      if (start == null || end == null || !end.isAfter(start)) continue;
      out.add(EpgEntry(
        title: _b64(e['title']) ?? '',
        description: _b64(e['description']),
        start: start,
        end: end,
      ));
    }
    out.sort((a, b) => a.start.compareTo(b.start));
    return out;
  }

  // ── Playback ─────────────────────────────────────────────────────────────

  /// Live container: admin preference if the account allows it, else whatever
  /// the account allows (ts first — the reliable one on Neo), else `ts`.
  String get liveFormat {
    final allowed = _allowedFormats;
    final pref = preferredLiveFormat.toLowerCase();
    if (allowed.isEmpty || allowed.contains(pref)) return pref;
    for (final f in const ['ts', 'm3u8']) {
      if (allowed.contains(f)) return f;
    }
    return pref;
  }

  @override
  Future<ResolvedStream> resolveStream(StreamRef ref) async => ResolvedStream(url: streamUri(ref));

  /// `/live|movie|series/{user}/{pass}/{id}.{ext}` on the panel host.
  Uri streamUri(StreamRef ref) {
    final (segment, ext) = switch (ref.kind) {
      MediaKind.live || MediaKind.sports => ('live', liveFormat),
      MediaKind.movie => ('movie', ref.extension ?? 'mp4'),
      MediaKind.series => ('series', ref.extension ?? 'mp4'),
    };
    final prefix = _base.pathSegments.where((p) => p.isNotEmpty);
    // Same scheme as the API after an https → http fallback.
    return _http.effective(_base).replace(pathSegments: [
      ...prefix,
      segment,
      credentials.username.trim(),
      credentials.password,
      '${ref.id}.$ext',
    ]);
  }

  @override
  void dispose() => _http.close();

  // ── Lenient field helpers ────────────────────────────────────────────────

  static List<Map<String, dynamic>> _list(Object? raw) {
    if (raw is List) return jsonMapList(raw);
    // A few panels answer an object keyed by index instead of a list.
    if (raw is Map) return jsonMapList(raw.values.toList());
    return const [];
  }

  static String? _id(Object? v) {
    final s = jsonStr(v)?.trim();
    return (s == null || s.isEmpty || s == 'null') ? null : s;
  }

  static String? _nonEmpty(Object? v) {
    final s = jsonStr(v)?.trim();
    return (s == null || s.isEmpty) ? null : s;
  }

  static String? _ext(Object? v) {
    final s = _nonEmpty(v)?.toLowerCase().replaceAll('.', '');
    return (s == null || !RegExp(r'^[a-z0-9]{2,5}$').hasMatch(s)) ? null : s;
  }

  static int? _tmdb(Object? v) {
    final n = jsonInt(v);
    return (n == null || n <= 0) ? null : n;
  }

  static String? _firstUrl(Object? v) {
    if (v is List) {
      for (final x in v) {
        final s = _nonEmpty(x);
        if (s != null && s.startsWith('http')) return s;
      }
      return null;
    }
    final s = _nonEmpty(v);
    return (s != null && s.startsWith('http')) ? s : null;
  }

  /// "Drama / Comedy", "Adventure, Family" → ["Drama", "Comedy"].
  static List<String> _genres(Object? v) => (_nonEmpty(v) ?? '')
      .split(RegExp(r'\s*[/,|]\s*'))
      .map((g) => g.trim())
      .where((g) => g.isNotEmpty)
      .toSet()
      .toList();

  /// First plausible year in "2023-07-06 (country)" / "2023".
  static int? _year(Object? v) {
    final s = jsonStr(v);
    if (s == null) return null;
    final m = RegExp(r'(19|20)\d{2}').firstMatch(s);
    return m == null ? null : int.parse(m.group(0)!);
  }

  /// "Valley Road (2023)" → 2023.
  static int? _yearInName(String name) {
    final m = RegExp(r'\((19|20)\d{2}\)').firstMatch(name);
    return m == null ? null : int.parse(m.group(0)!.substring(1, 5));
  }

  static DateTime? _unix(Object? v) {
    final n = jsonInt(v);
    return (n == null || n <= 0) ? null : DateTime.fromMillisecondsSinceEpoch(n * 1000, isUtc: true);
  }

  static DateTime? _parseTime(Object? v) {
    final s = jsonStr(v)?.trim();
    if (s == null || s.isEmpty) return null;
    return DateTime.tryParse(s.replaceFirst(' ', 'T'));
  }

  /// EPG titles are base64 on most panels, plain text on some.
  static String? _b64(Object? v) {
    final s = jsonStr(v)?.trim();
    if (s == null || s.isEmpty) return null;
    if (RegExp(r'^[A-Za-z0-9+/]+=*$').hasMatch(s) && s.length % 4 == 0) {
      try {
        final t = utf8.decode(base64.decode(s)).trim();
        if (t.isNotEmpty) return t;
      } catch (_) {
        // not base64 after all
      }
    }
    return s;
  }
}
