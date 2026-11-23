import 'dart:convert';

import 'package:domain/domain.dart';

import '../../backend/json_util.dart';
import '../../diag/diag.dart';
import '../../remote/json_read.dart';
import '../provider_adapter.dart';
import '../provider_http.dart';
import '../provider_models.dart';

/// Stalker / Ministra portals ("MAG", login = portal URL + MAC).
/// Notes: docs/PROVIDER_PROTOCOLS.md §3. Measured on a real portal 2026-11-15:
/// endpoint `/portal.php`, 14 items per page, expiry in `account_info.phone`,
/// live `create_link` needs the `ffmpeg http://localhost/ch/{id}_` form,
/// series → seasons (`id:season`) whose `series` list holds episode numbers.
///
/// The MAC is a value sent in a cookie — not the device's network MAC — so a
/// line keeps working on any Wi-Fi / mobile data.
class StalkerAdapter implements ProviderAdapter, PagedLists {
  StalkerAdapter(
    this.credentials, {
    ProviderHttp? http,
    this.timezone = 'UTC',
    this.allPagesLimit = 30,
    DateTime Function()? clock,
  })  : _http = http ?? ProviderHttp(),
        _clock = clock ?? DateTime.now {
    final portal = credentials.portalUri;
    final mac = credentials.normalizedMac;
    if (portal == null) throw const ProviderFailure(ProviderFailureKind.invalidInput, 'portal');
    if (mac == null) throw const ProviderFailure(ProviderFailureKind.invalidInput, 'mac');
    _portal = portal;
    _mac = mac;
  }

  static void register({ProviderLimits limits = const ProviderLimits(), String timezone = 'UTC'}) {
    ProviderAdapterFactory.register(
      ProviderKind.stalker,
      (c) => StalkerAdapter(c as StalkerCredentials, http: ProviderHttp(limits: limits), timezone: timezone),
    );
  }

  final StalkerCredentials credentials;

  /// IANA zone sent to the portal (EPG times, some expiry texts).
  final String timezone;

  /// "All" lists (no category) are capped to this many pages (14 items
  /// each): big portals have tens of thousands of items. Browse by category.
  final int allPagesLimit;

  final ProviderHttp _http;
  final DateTime Function() _clock;
  late final Uri _portal;
  late final String _mac;

  Uri? _api;
  String? _token;

  /// Items seen in lists, for details without another request.
  final _vod = <String, Map<String, dynamic>>{};

  static const _ua =
      'Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 (KHTML, like Gecko) MAG200 stbapp ver: 2 rev: 250 Safari/533.3';

  @override
  ProviderKind get kind => ProviderKind.stalker;

  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities(
        live: true,
        movies: true,
        series: true,
        epg: true,
        catchup: true,
        linksExpire: true,
        // Pages of 14 items and a slow, huge get_all_channels (timed out on the
        // user's portal, 2026-11-15) → like the panel's own web player:
        // category lists at once, a category's items when it is opened.
        lists: {
          MediaKind.live: ListStrategy.onDemand,
          MediaKind.movie: ListStrategy.onDemand,
          MediaKind.series: ListStrategy.onDemand,
        },
      );

  Map<String, String> get _headers => {
        'User-Agent': _ua,
        'X-User-Agent': 'Model: MAG250; Link: WiFi',
        'Referer': _portal.toString().endsWith('/') ? '$_portal' : '$_portal/',
        'Cookie': 'mac=${Uri.encodeComponent(_mac)}; stb_lang=en; timezone=${Uri.encodeComponent(timezone)}',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  /// Where the API lives, most likely first. `…/c/` is the web UI.
  List<Uri> get endpointCandidates {
    var path = _portal.path;
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    if (path.endsWith('/c')) path = path.substring(0, path.length - 2);
    final root = _portal.replace(path: '');
    final out = <Uri>[
      _portal.replace(path: '$path/portal.php'),
      _portal.replace(path: '$path/server/load.php'),
      root.replace(path: '/stalker_portal/server/load.php'),
      root.replace(path: '/portal.php'),
    ];
    final seen = <String>{};
    return [for (final u in out) if (seen.add('$u')) u];
  }

  // ── Session ──────────────────────────────────────────────────────────────

  Future<Object?> _get(Uri api, Map<String, String> params, {bool auth = false, bool priority = false}) async {
    final text = await _http.getText(
      api.replace(queryParameters: {...params, 'JsHttpRequest': '1-xml'}),
      headers: _headers,
      auth: auth,
      priority: priority,
      wholeList: params['action'] == 'get_all_channels',
    );
    if (text.contains('Authorization failed')) {
      throw const ProviderFailure(ProviderFailureKind.unauthorized, 'token');
    }
    final body = await _http.decodeJson(text);
    return body is Map ? body['js'] : null;
  }

  Future<void> _handshake() async {
    ProviderFailure? last;
    for (final api in _api == null ? endpointCandidates : [_api!]) {
      try {
        _token = null;
        final js = jsonMap(await _get(api, {'type': 'stb', 'action': 'handshake', 'token': ''}, auth: true));
        final token = jsonStr(js['token'])?.trim();
        if (token != null && token.isNotEmpty) {
          Diag.panel('stalker endpoint ${Diag.panelUrl(api)} → handshake OK');
          _api = api;
          _token = token;
          return;
        }
        Diag.panel('stalker endpoint ${Diag.panelUrl(api)} → no token in reply');
      } on ProviderFailure catch (f) {
        Diag.panel('stalker endpoint ${Diag.panelUrl(api)} → ${f.kind.name}, trying next');
        last = f;
        // Wrong path answers 404/HTML: try the next one. Network errors and
        // timeouts mean the portal itself is unreachable.
        if (f.kind == ProviderFailureKind.network || f.kind == ProviderFailureKind.timeout) rethrow;
      }
    }
    throw last ?? const ProviderFailure(ProviderFailureKind.badResponse, 'no portal endpoint');
  }

  Future<Map<String, dynamic>> _profile() async => jsonMap(await _get(_api!, {
        'type': 'stb',
        'action': 'get_profile',
        'hd': '1',
        'stb_type': 'MAG250',
        'auth_second_step': '1',
      }, auth: true));

  /// Calls the API; on an expired token, handshakes again once and retries.
  Future<Object?> _call(Map<String, String> params, {bool priority = false}) async {
    if (_token == null) await _login();
    try {
      return await _get(_api!, params, priority: priority);
    } on ProviderFailure catch (f) {
      if (f.kind != ProviderFailureKind.unauthorized) rethrow;
      await _login();
      return _get(_api!, params, priority: priority);
    }
  }

  /// The portal's parental password (`parent_password`, set on the panel
  /// for the account) — the adult PIN, as on a MAG box. Null until login.
  String? get parentalPin => _parentalPin;
  String? _parentalPin;

  Future<Map<String, dynamic>> _login() async {
    await _handshake();
    final p = await _profile();
    final pin = jsonStr(p['parent_password'])?.trim();
    _parentalPin = (pin == null || pin.isEmpty) ? null : pin;
    Diag.panel('stalker profile: status=${p['status']}, blocked=${p['blocked']}, has id ${p['id'] != null}');
    checkProfile(p);
    return p;
  }

  /// MAC refused / blocked → failure. Portals use `status` 0 = OK.
  static void checkProfile(Map<String, dynamic> p) {
    if (p.isEmpty) throw const ProviderFailure(ProviderFailureKind.unauthorized, 'no profile');
    if (jsonBool(p['blocked']) == true) throw const ProviderFailure(ProviderFailureKind.banned, 'blocked');
    final status = jsonInt(p['status']) ?? 0;
    if (status != 0) throw ProviderFailure(ProviderFailureKind.unauthorized, 'status $status');
  }

  @override
  Future<ProviderAccount> authenticate() async {
    final profile = await _login();
    Map<String, dynamic> info = const {};
    try {
      info = jsonMap(await _get(_api!, {'type': 'account_info', 'action': 'get_main_info'}));
    } on ProviderFailure {
      // Not every portal has account_info; the profile is enough to connect.
    }
    final expires = parseExpiry(info, profile);
    if (expires != null && expires.isBefore(_clock())) {
      throw const ProviderFailure(ProviderFailureKind.expired, 'expired');
    }
    return ProviderAccount(status: ConnectionStatus.active, expiresAt: expires, serverTimezone: timezone);
  }

  /// Expiry lives in different fields per portal: `phone` ("November 16,
  /// 2026, 9:29 am"), `end_date`, or the profile's billing dates.
  static DateTime? parseExpiry(Map<String, dynamic> info, Map<String, dynamic> profile) {
    for (final v in [info['end_date'], info['phone'], profile['expire_billing_date'], profile['tariff_expired_date']]) {
      final d = _parseLooseDate(jsonStr(v));
      if (d != null) return d;
    }
    return null;
  }

  // ── Categories & lists ───────────────────────────────────────────────────

  List<ProviderCategory> _cats(Object? raw) => [
        for (final c in jsonMapList(raw))
          if (_id(c['id']) case final id? when id != '*')
            ProviderCategory(id: id, name: (jsonStr(c['title']) ?? '').trim(), adult: jsonBool(c['censored']) ?? false),
      ];

  @override
  Future<List<ProviderCategory>> liveCategories() async =>
      _cats(await _call({'type': 'itv', 'action': 'get_genres'}));

  @override
  Future<List<ProviderCategory>> movieCategories() async =>
      _cats(await _call({'type': 'vod', 'action': 'get_categories'}));

  @override
  Future<List<ProviderCategory>> seriesCategories() async {
    final own = _cats(await _call({'type': 'series', 'action': 'get_categories'}));
    _seriesInVod = own.isEmpty;
    if (own.isNotEmpty) return own; // portal with its own series section (most portals)
    // Older Ministra portals keep series inside the movie categories
    // (entries with is_series = 1): the same categories, series only.
    Diag.event('PANEL', 'stalker: no series section on this portal → series are read from the movie categories');
    return movieCategories();
  }

  /// null = not checked yet; true = series live inside the VOD lists.
  bool? _seriesInVod;

  Future<bool> _seriesFromVod() async {
    if (_seriesInVod == null) await seriesCategories();
    return _seriesInVod ?? false;
  }

  /// A series entry of a VOD list → its seasons / episodes (the entry
  /// carries `cmd` and the episode numbers in `series`).
  ProviderSeriesDetails? _vodSeriesDetails(Map<String, dynamic> raw) {
    final s = parseSeries(raw, portal: _portal);
    if (s == null || _nonEmpty(raw['cmd']) == null || raw['series'] is! List || (raw['series'] as List).isEmpty) return null;
    // One entry = one season; its title ("Dune 2", "24") is not a season.
    return parseSeasons([{...raw, 'name': ''}], s.id, s);
  }

  /// Page 1, then the remaining pages in parallel (ProviderHttp caps it).
  Future<List<Map<String, dynamic>>> _paged(Map<String, String> params, {int? maxPages, bool priority = false}) async {
    final first = jsonMap(await _call({...params, 'p': '1'}, priority: priority));
    final items = [...jsonMapList(first['data'])];
    final total = jsonInt(first['total_items']) ?? items.length;
    final per = jsonInt(first['max_page_items']) ?? (items.isEmpty ? 1 : items.length);
    var pages = per <= 0 ? 1 : (total / per).ceil();
    if (maxPages != null && pages > maxPages) pages = maxPages;
    // One page after another: firing every page at once (~100 requests for
    // a big category) made portals answer HTTP 429.
    for (var p = 2; p <= pages; p++) {
      items.addAll(jsonMapList(jsonMap(await _call({...params, 'p': '$p'}, priority: priority))['data']));
    }
    return items;
  }

  /// One page (the user is waiting: priority lane).
  Future<(List<Map<String, dynamic>>, int)> _onePage(Map<String, String> params, int page) async {
    final js = jsonMap(await _call({...params, 'p': '$page'}, priority: true));
    final items = jsonMapList(js['data']);
    final total = jsonInt(js['total_items']) ?? items.length;
    final per = jsonInt(js['max_page_items']) ?? (items.isEmpty ? 1 : items.length);
    final pages = per <= 0 || total <= 0 ? 1 : (total / per).ceil();
    return (items, pages < page ? page : pages);
  }

  @override
  Future<ProviderPage<ProviderChannel>> liveChannelsPage(String categoryId, int page) async {
    final (raw, pages) = await _onePage({'type': 'itv', 'action': 'get_ordered_list', 'genre': categoryId, 'sortby': 'number'}, page);
    return ProviderPage(parseChannels(raw, portal: _portal), page: page, pages: pages);
  }

  @override
  Future<ProviderPage<ProviderMovie>> moviesPage(String categoryId, int page) async {
    final (raw, pages) = await _onePage({'type': 'vod', 'action': 'get_ordered_list', 'category': categoryId, 'sortby': 'added'}, page);
    final movies = _movies(raw);
    // Series-inside-VOD portals only: a page of series only = a series
    // category; don't page through it under Movies. Other portals: as before.
    final stop = _seriesInVod == true && movies.isEmpty && raw.isNotEmpty;
    return ProviderPage(movies, page: page, pages: stop ? page : pages);
  }

  @override
  Future<ProviderPage<ProviderSeries>> seriesPage(String categoryId, int page) async {
    if (await _seriesFromVod()) {
      final (raw, pages) = await _onePage({'type': 'vod', 'action': 'get_ordered_list', 'category': categoryId, 'sortby': 'added'}, page);
      final entries = [for (final m in raw) if (jsonBool(m['is_series']) == true) m];
      // No series on this page of a movie category: stop here (portals
      // keep series together; scanning every page would hammer the panel).
      return ProviderPage(_series(entries), page: page, pages: entries.isEmpty ? page : pages,
          details: [for (final m in entries) ?_vodSeriesDetails(m)]);
    }
    final (raw, pages) = await _onePage({'type': 'series', 'action': 'get_ordered_list', 'category': categoryId, 'sortby': 'added'}, page);
    return ProviderPage(_series(raw), page: page, pages: pages);
  }

  @override
  Future<List<ProviderChannel>> liveChannels({String? categoryId, bool priority = false}) async {
    final all = categoryId == null || categoryId.isEmpty;
    final raw = all
        ? jsonMapList(jsonMap(await _call({'type': 'itv', 'action': 'get_all_channels'}, priority: priority))['data'])
        : await _paged({'type': 'itv', 'action': 'get_ordered_list', 'genre': categoryId, 'sortby': 'number'}, priority: priority);
    return parseChannels(raw, portal: _portal);
  }

  static List<ProviderChannel> parseChannels(List<Map<String, dynamic>> raw, {Uri? portal}) => [
        for (final c in raw)
          if (_id(c['id']) case final id?)
            if (!isProviderAdOrHeaderChannel(jsonStr(c['name']) ?? ''))
              ProviderChannel(
                id: id,
                name: (jsonStr(c['name']) ?? '').trim(),
                stream: StreamRef(kind: MediaKind.live, id: id, command: _nonEmpty(c['cmd'])),
                number: jsonInt(c['number']),
                logoUrl: _absUrl(c['logo'], portal),
                categoryId: _id(c['tv_genre_id']),
                epgId: _nonEmpty(c['xmltv_id']),
                catchupDays: (jsonBool(c['archive']) ?? false) || (jsonBool(c['enable_tv_archive']) ?? false)
                    ? (jsonInt(c['tv_archive_duration']) ?? 0)
                    : 0,
                adult: jsonBool(c['censored']) ?? false,
              ),
      ];

  @override
  Future<List<ProviderMovie>> movies({String? categoryId, bool priority = false}) async {
    final raw = await _paged(
      {'type': 'vod', 'action': 'get_ordered_list', 'category': _catOrAll(categoryId), 'sortby': 'added'},
      maxPages: _isAll(categoryId) ? allPagesLimit : null,
      priority: priority,
    );
    return _movies(raw);
  }

  List<ProviderMovie> _movies(List<Map<String, dynamic>> raw) {
    final out = <ProviderMovie>[];
    for (final m in raw) {
      if (jsonBool(m['is_series']) == true) continue;
      final mv = parseMovie(m, portal: _portal);
      if (mv == null) continue;
      _vod[mv.id] = m;
      out.add(mv);
    }
    return out;
  }

  /// [portal]: makes relative poster paths full addresses (some portals
  /// send "/stalker_portal/screenshots/…": no image showed).
  static ProviderMovie? parseMovie(Map<String, dynamic> m, {Uri? portal}) {
    final id = _id(m['id']);
    if (id == null) return null;
    final name = (jsonStr(m['name']) ?? jsonStr(m['o_name']) ?? '').trim();
    return ProviderMovie(
      id: id,
      name: name,
      stream: StreamRef(kind: MediaKind.movie, id: id, command: _nonEmpty(m['cmd'])),
      posterUrl: _absUrl(m['screenshot_uri'], portal) ?? _nonEmpty(m['screenshot_uri']),
      rating: jsonDouble(m['rating_imdb']) ?? jsonDouble(m['rating_kinopoisk']),
      year: _year(m['year']) ?? _yearInName(name),
      categoryId: _id(m['category_id']),
      addedSec: _dateSec(m['added']),
      tmdbId: _tmdb(m['tmdb_id']),
      adult: jsonBool(m['censored']) ?? false,
    );
  }

  @override
  Future<List<ProviderSeries>> series({String? categoryId, bool priority = false}) async {
    if (await _seriesFromVod()) {
      final raw = await _paged(
        {'type': 'vod', 'action': 'get_ordered_list', 'category': _catOrAll(categoryId), 'sortby': 'added'},
        maxPages: _isAll(categoryId) ? allPagesLimit : null,
        priority: priority,
      );
      return _series([for (final m in raw) if (jsonBool(m['is_series']) == true) m]);
    }
    final raw = await _paged(
      {'type': 'series', 'action': 'get_ordered_list', 'category': _catOrAll(categoryId), 'sortby': 'added'},
      maxPages: _isAll(categoryId) ? allPagesLimit : null,
      priority: priority,
    );
    return _series(raw);
  }

  List<ProviderSeries> _series(List<Map<String, dynamic>> raw) {
    final out = <ProviderSeries>[];
    for (final s in raw) {
      final p = parseSeries(s, portal: _portal);
      if (p == null) continue;
      _vod[p.id] = s;
      out.add(p);
    }
    return out;
  }

  static ProviderSeries? parseSeries(Map<String, dynamic> s, {Uri? portal}) {
    final id = _id(s['id']);
    if (id == null) return null;
    final name = (jsonStr(s['name']) ?? '').trim();
    return ProviderSeries(
      id: id,
      name: name,
      posterUrl: _absUrl(s['screenshot_uri'], portal) ?? _nonEmpty(s['screenshot_uri']),
      plot: _nonEmpty(s['description']),
      genres: _genres(s['genres_str']),
      rating: jsonDouble(s['rating_imdb']) ?? jsonDouble(s['rating_kinopoisk']),
      year: _year(s['year']) ?? _yearInName(name),
      categoryId: _id(s['category_id']),
      addedSec: _dateSec(s['added']),
      tmdbId: _tmdb(s['tmdb_id']),
      adult: jsonBool(s['censored']) ?? false,
    );
  }

  // ── Details ──────────────────────────────────────────────────────────────

  /// Stalker lists already carry the details; built from the item seen in
  /// [movies] (open a category first).
  @override
  Future<ProviderMovieDetails> movieDetails(String movieId) async {
    final m = _vod[movieId];
    if (m == null) throw const ProviderFailure(ProviderFailureKind.badResponse, 'movie not loaded');
    return parseMovieDetails(m)!;
  }

  static ProviderMovieDetails? parseMovieDetails(Map<String, dynamic> m) {
    final movie = parseMovie(m);
    if (movie == null) return null;
    final minutes = jsonInt(m['time']);
    return ProviderMovieDetails(
      movie: movie,
      plot: _nonEmpty(m['description']),
      genres: _genres(m['genres_str']),
      cast: _nonEmpty(m['actors']),
      director: _nonEmpty(m['director']),
      durationSec: (minutes == null || minutes <= 0) ? null : minutes * 60,
    );
  }

  /// Seasons (`movie_id`, `season_id=0`); each season lists its episode
  /// numbers in `series` and plays through its own `cmd` + episode number.
  @override
  Future<ProviderSeriesDetails> seriesDetails(String seriesId) async {
    final entry = _vod[seriesId];
    if (entry != null && jsonBool(entry['is_series']) == true) {
      final d = _vodSeriesDetails(entry);
      if (d != null) return d; // series inside the VOD lists: no request
    }
    // Series inside the VOD lists: their seasons come from the vod module.
    final vodMode = _seriesInVod == true || (entry != null && jsonBool(entry['is_series']) == true);
    final seasons = await _paged({
      'type': vodMode ? 'vod' : 'series',
      'action': 'get_ordered_list',
      'movie_id': seriesId,
      'season_id': '0',
      'episode_id': '0',
      'sortby': 'added',
    }, priority: true);
    final cached = _vod[seriesId];
    final info = (cached == null ? null : parseSeries(cached, portal: _portal)) ??
        ProviderSeries(id: seriesId, name: (jsonStr(seasons.firstOrNull?['name']) ?? '').trim());
    var d = parseSeasons(seasons, seriesId, info);
    if (vodMode && d.episodes.isEmpty && seasons.isNotEmpty) {
      // Newer Ministra: seasons carry no episode numbers, so each season's
      // episodes are asked separately (one request per season, in order).
      d = await _episodesPerSeason(seriesId, seasons, info);
    }
    if (d.episodes.isEmpty) {
      Diag.panel('stalker series $seriesId: no episodes understood: ${seasons.length} rows, '
          'fields ${seasons.firstOrNull?.keys.take(14).toList()}');
    }
    return d;
  }

  /// (series, season, episode) ids behind an episode stream id, for the
  /// files lookup when the portal says "nothing_to_play".
  final _episodeIds = <String, (String, String, String)>{};

  /// Set once the file list gave the link after the usual commands failed
  /// (newer Ministra): later titles go to the file list first, skipping
  /// create_link calls that only answer "nothing_to_play". Portals where the
  /// usual commands work never set it.
  bool _filesFirst = false;

  Future<ProviderSeriesDetails> _episodesPerSeason(
      String seriesId, List<Map<String, dynamic>> seasons, ProviderSeries info) async {
    final episodes = <int, List<ProviderEpisode>>{};
    var fallbackSeason = 0;
    for (final s in seasons) {
      fallbackSeason++;
      final sid = _id(s['id']);
      if (sid == null) continue;
      final season = jsonInt(s['season_number']) ?? _seasonNumber(sid, jsonStr(s['name'])) ?? fallbackSeason;
      final rows = await _paged({
        'type': 'vod',
        'action': 'get_ordered_list',
        'movie_id': seriesId,
        'season_id': sid,
        'episode_id': '0',
      }, priority: true);
      var i = 0;
      for (final e in rows) {
        i++;
        final eid = _id(e['id']);
        if (eid == null) continue;
        final n = jsonInt(e['series_number']) ?? jsonInt(e['episode_number']) ?? i;
        final id = '$sid#$n';
        _episodeIds[id] = (seriesId, sid, eid);
        (episodes[season] ??= []).add(ProviderEpisode(
          id: id,
          seriesId: seriesId,
          season: season,
          number: n,
          title: (jsonStr(e['name']) ?? '').trim(),
          stream: StreamRef(kind: MediaKind.series, id: id, command: _nonEmpty(e['cmd'])),
          plot: _nonEmpty(e['description']),
          stillUrl: _absUrl(e['screenshot_uri'], _portal),
        ));
      }
    }
    for (final l in episodes.values) {
      l.sort((a, b) => a.number.compareTo(b.number));
    }
    return ProviderSeriesDetails(series: info, episodes: episodes);
  }

  /// Newer Ministra: the playable command sits in the title's file list.
  Future<Uri?> _linkFromFiles(String movieId, {String seasonId = '0', String episodeId = '0', String series = ''}) async {
    final files = await _paged({
      'type': 'vod',
      'action': 'get_ordered_list',
      'movie_id': movieId,
      'season_id': seasonId,
      'episode_id': episodeId,
    }, priority: true);
    for (final f in files.take(3)) {
      // File rows (newer Ministra) have no cmd: the file command is
      // "/media/file_<id>.mpg"; some portals give a direct url as well.
      final fileId = _id(f['id']);
      for (final cmd in [_nonEmpty(f['cmd']), if (fileId != null) '/media/file_$fileId.mpg']) {
        if (cmd == null) continue;
        final url = await _createLink('vod', cmd, series: series);
        if (url != null) return url;
      }
      final direct = cleanLink(_nonEmpty(f['url']));
      if (direct != null && !hasEmptyStreamParam(direct)) {
        Diag.panel('stalker files of $movieId: playing the file\'s own address (${f['protocol'] ?? '?'})');
        return _http.effective(direct);
      }
    }
    Diag.panel('stalker files of $movieId: no playable file: ${files.length} rows, '
        'fields ${files.firstOrNull?.keys.take(14).toList()}');
    return null;
  }

  static ProviderSeriesDetails parseSeasons(List<Map<String, dynamic>> seasons, String seriesId, ProviderSeries series) {
    final episodes = <int, List<ProviderEpisode>>{};
    var fallbackSeason = 0;
    for (final s in seasons) {
      fallbackSeason++;
      final seasonId = _id(s['id']);
      final cmd = _nonEmpty(s['cmd']);
      if (seasonId == null || cmd == null) continue;
      final season = _seasonNumber(seasonId, jsonStr(s['name'])) ?? fallbackSeason;
      final numbers = (s['series'] is List ? (s['series'] as List) : const [])
          .map(jsonInt)
          .whereType<int>()
          .toList()
        ..sort();
      final list = episodes.putIfAbsent(season, () => []);
      for (final n in numbers) {
        final id = '$seasonId#$n';
        list.add(ProviderEpisode(
          id: id,
          seriesId: seriesId,
          season: season,
          number: n,
          title: '', // portals send no episode titles; the app labels "Episode n"
          stream: StreamRef(kind: MediaKind.series, id: id, command: cmd),
          plot: _nonEmpty(s['description']),
          stillUrl: _nonEmpty(s['screenshot_uri']),
        ));
      }
    }
    episodes.removeWhere((_, l) => l.isEmpty);
    return ProviderSeriesDetails(series: series, episodes: episodes);
  }

  // ── EPG ──────────────────────────────────────────────────────────────────

  @override
  Future<List<EpgEntry>> shortEpg(ProviderChannel channel, {int limit = 4}) async =>
      parseShortEpg(await _call({'type': 'itv', 'action': 'get_short_epg', 'ch_id': channel.id, 'size': '$limit'}, priority: true));

  static List<EpgEntry> parseShortEpg(Object? raw) {
    final out = <EpgEntry>[];
    for (final e in jsonMapList(raw)) {
      final start = _unix(e['start_timestamp']);
      final end = _unix(e['stop_timestamp']);
      if (start == null || end == null || !end.isAfter(start)) continue;
      out.add(EpgEntry(
        title: (jsonStr(e['name']) ?? '').trim(),
        description: _nonEmpty(e['descr']),
        start: start,
        end: end,
      ));
    }
    out.sort((a, b) => a.start.compareTo(b.start));
    return out;
  }

  // ── Playback ─────────────────────────────────────────────────────────────

  /// Asks the portal for a fresh, short-lived link right before playing.
  @override
  Future<ResolvedStream> resolveStream(StreamRef ref) async {
    switch (ref.kind) {
      case MediaKind.live:
      case MediaKind.sports:
        // The list `cmd` often yields a link with an empty `stream=` (seen
        // live); the classic `localhost/ch/{id}_` form always works.
        for (final cmd in [ref.command, 'ffmpeg http://localhost/ch/${ref.id}_']) {
          if (cmd == null) continue;
          final url = await _createLink('itv', cmd);
          if (url != null && !hasEmptyStreamParam(url)) return ResolvedStream(url: url, headers: {'User-Agent': _ua});
        }
        throw const ProviderFailure(ProviderFailureKind.badResponse, 'no live link');
      case MediaKind.movie:
        if (_filesFirst) {
          final fromFiles = await _linkFromFiles(ref.id);
          if (fromFiles != null) return ResolvedStream(url: fromFiles, headers: {'User-Agent': _ua});
        }
        // The movie's own cmd first (as before); then the standard Ministra
        // form — some portals send no / an unusable cmd in their lists.
        for (final cmd in [ref.command, '/media/${ref.id}.mpg']) {
          if (cmd == null) continue;
          final url = await _createLink('vod', cmd);
          if (url != null && !hasEmptyStreamParam(url)) return ResolvedStream(url: url, headers: {'User-Agent': _ua});
        }
        // "nothing_to_play": newer Ministra keeps the command in the file list.
        if (!_filesFirst) {
          final fromFiles = await _linkFromFiles(ref.id);
          if (fromFiles != null) {
            _filesFirst = true;
            Diag.panel('stalker: links come from the file list on this portal → tried first from now on');
            return ResolvedStream(url: fromFiles, headers: {'User-Agent': _ua});
          }
        }
        throw const ProviderFailure(ProviderFailureKind.badResponse, 'no movie link');
      case MediaKind.series:
        final hash = ref.id.lastIndexOf('#');
        final episode = hash < 0 ? '' : ref.id.substring(hash + 1);
        final entry = hash < 0 ? ref.id : ref.id.substring(0, hash);
        final ids = _episodeIds[ref.id];
        if (_filesFirst && ids != null) {
          final fromFiles = await _linkFromFiles(ids.$1, seasonId: ids.$2, episodeId: ids.$3);
          if (fromFiles != null) return ResolvedStream(url: fromFiles, headers: {'User-Agent': _ua});
        }
        // The season's / entry's own cmd first (as before), then the
        // standard Ministra form for this entry.
        for (final cmd in [ref.command, if (RegExp(r'^\d+$').hasMatch(entry)) '/media/$entry.mpg']) {
          if (cmd == null) continue;
          final url = await _createLink('vod', cmd, series: episode);
          if (url != null) return ResolvedStream(url: url, headers: {'User-Agent': _ua});
        }
        if (ids != null && !_filesFirst) {
          final fromFiles = await _linkFromFiles(ids.$1, seasonId: ids.$2, episodeId: ids.$3);
          if (fromFiles != null) {
            _filesFirst = true;
            return ResolvedStream(url: fromFiles, headers: {'User-Agent': _ua});
          }
        }
        throw const ProviderFailure(ProviderFailureKind.badResponse, 'no episode link');
    }
  }

  Future<Uri?> _createLink(String type, String cmd, {String series = ''}) async {
    final js = jsonMap(await _call(priority: true, {
      'type': type,
      'action': 'create_link',
      'cmd': cmd,
      'series': series,
      'forced_storage': 'undefined',
      'disable_ad': '0',
      'download': '0',
    }));
    final raw = jsonStr(js['cmd']);
    final link = cleanLink(raw);
    if (link == null || hasEmptyStreamParam(link)) {
      // Shape only (never the link): what did the portal send?
      final shape = raw == null || raw.trim().isEmpty
          ? 'no cmd (reply keys ${js.keys.take(6).toList()}${js['error'] != null ? ', error "${Diag.panelText('${js['error']}')}"' : ''})'
          : link == null
              ? 'no http address (starts "${Diag.panelText(raw.trim().split(' ').first)}", ${raw.length} chars)'
              : 'empty stream id (${link.path})';
      Diag.panel('stalker create_link $type${series.isEmpty ? '' : ' (episode $series)'}: unusable reply — $shape');
      return null;
    }
    return _http.effective(link);
  }

  /// "ffmpeg http://…" / "auto http://…" → the URL.
  static Uri? cleanLink(String? cmd) {
    final s = cmd?.trim() ?? '';
    if (s.isEmpty) return null;
    final i = s.indexOf(RegExp(r'(https?|rtmp|rtsp)://'));
    if (i < 0) return null;
    return Uri.tryParse(s.substring(i).split(' ').first);
  }

  static bool hasEmptyStreamParam(Uri u) =>
      u.queryParameters.containsKey('stream') && u.queryParameters['stream']!.isEmpty;

  @override
  void dispose() => _http.close();

  // ── Lenient helpers ──────────────────────────────────────────────────────

  static bool _isAll(String? c) => c == null || c.isEmpty || c == '*';
  static String _catOrAll(String? c) => _isAll(c) ? '*' : c!;

  static String? _id(Object? v) {
    final s = jsonStr(v)?.trim();
    return (s == null || s.isEmpty || s == 'null') ? null : s;
  }

  static String? _nonEmpty(Object? v) {
    final s = jsonStr(v)?.trim();
    return (s == null || s.isEmpty) ? null : s;
  }

  /// Logos may be relative to the portal ("misc/logos/…").
  static String? _absUrl(Object? v, Uri? portal) {
    final s = _nonEmpty(v);
    if (s == null) return null;
    if (s.startsWith('http://') || s.startsWith('https://')) return s;
    if (portal == null) return null;
    return portal.resolve(s.startsWith('/') ? s : '/stalker_portal/$s').toString();
  }

  static int? _tmdb(Object? v) {
    final n = jsonInt(v);
    return (n == null || n <= 0) ? null : n;
  }

  static List<String> _genres(Object? v) => (_nonEmpty(v) ?? '')
      .split(RegExp(r'\s*[/,|]\s*'))
      .map((g) => g.trim())
      .where((g) => g.isNotEmpty)
      .toSet()
      .toList();

  static int? _year(Object? v) {
    final m = RegExp(r'(19|20)\d{2}').firstMatch(jsonStr(v) ?? '');
    return m == null ? null : int.parse(m.group(0)!);
  }

  static int? _yearInName(String name) {
    final m = RegExp(r'\((19|20)\d{2}\)').firstMatch(name);
    return m == null ? null : int.parse(m.group(0)!.substring(1, 5));
  }

  /// "2026-11-14 19:06:00" → unix seconds.
  static int? _dateSec(Object? v) {
    final s = jsonStr(v)?.trim();
    if (s == null || s.isEmpty || s.startsWith('0000')) return null;
    final d = DateTime.tryParse(s.replaceFirst(' ', 'T'));
    return d == null ? null : d.millisecondsSinceEpoch ~/ 1000;
  }

  static DateTime? _unix(Object? v) {
    final n = jsonInt(v);
    return (n == null || n <= 0) ? null : DateTime.fromMillisecondsSinceEpoch(n * 1000, isUtc: true);
  }

  /// "49938:2" or "Season 2" → 2.
  static int? _seasonNumber(String seasonId, String? name) {
    final colon = seasonId.lastIndexOf(':');
    if (colon >= 0) {
      final n = int.tryParse(seasonId.substring(colon + 1));
      if (n != null) return n;
    }
    final m = RegExp(r'(\d+)').firstMatch(name ?? '');
    return m == null ? null : int.parse(m.group(1)!);
  }

  static const _months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  /// "November 16, 2026, 9:29 am", "2026-11-16 09:29:00", "16.11.2026",
  /// unix seconds. Unlimited / zero dates → null.
  static DateTime? _parseLooseDate(String? raw) {
    final s = raw?.trim() ?? '';
    if (s.isEmpty || s.startsWith('0000') || s.toLowerCase().contains('unlimit')) return null;
    if (RegExp(r'^\d{9,11}$').hasMatch(s)) {
      return DateTime.fromMillisecondsSinceEpoch(int.parse(s) * 1000, isUtc: true);
    }
    final iso = DateTime.tryParse(s.replaceFirst(' ', 'T'));
    if (iso != null) return iso;
    final m = RegExp(r'([A-Za-z]{3})[a-z]*\.?\s+(\d{1,2}),?\s+(\d{4})(?:,?\s+(\d{1,2}):(\d{2})\s*([ap]m)?)?', caseSensitive: false)
        .firstMatch(s);
    if (m != null) {
      final month = _months[m.group(1)!.toLowerCase()];
      if (month == null) return null;
      var hour = int.tryParse(m.group(4) ?? '') ?? 0;
      final ampm = m.group(6)?.toLowerCase();
      if (ampm == 'pm' && hour < 12) hour += 12;
      if (ampm == 'am' && hour == 12) hour = 0;
      return DateTime(int.parse(m.group(3)!), month, int.parse(m.group(2)!), hour, int.tryParse(m.group(5) ?? '') ?? 0);
    }
    final dmy = RegExp(r'^(\d{1,2})[./-](\d{1,2})[./-](\d{4})').firstMatch(s);
    if (dmy != null) {
      return DateTime(int.parse(dmy.group(3)!), int.parse(dmy.group(2)!), int.parse(dmy.group(1)!));
    }
    return null;
  }

  /// Decodes the base64 JSON some portals put in VOD `cmd` (for diagnostics).
  static Map<String, dynamic>? decodeVodCmd(String cmd) {
    try {
      return jsonMap(jsonDecode(utf8.decode(base64.decode(base64.normalize(cmd.trim())))));
    } catch (_) {
      return null;
    }
  }
}
