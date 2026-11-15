import 'package:domain/domain.dart';

/// Panel protocols the app can talk to. The list shown on "Choose your panel"
/// comes from the admin config (`onboarding_panel_types`); this enum is what the
/// app knows how to speak. An unknown key from the server is simply not offered.
enum ProviderKind {
  xtream,
  m3u,
  stalker;

  static ProviderKind? fromKey(String? key) {
    for (final k in values) {
      if (k.name == key?.trim().toLowerCase()) return k;
    }
    return null;
  }
}

/// Spec §3.5 — one status for every connection. Never assume a panel is active
/// because it worked last time: [ProviderAdapter.authenticate] re-checks.
enum ConnectionStatus {
  pending,
  connecting,
  connected,
  synchronizing,
  active,
  expired,
  unauthorized,
  temporarilyUnavailable,
  invalidConfiguration,
  disabled,
  removed;

  /// The user can browse and play.
  bool get isUsable =>
      this == connected || this == synchronizing || this == active;

  /// Retrying later may help (as opposed to the user fixing something).
  bool get isTransient => this == temporarilyUnavailable || this == connecting;
}

/// Why a provider call failed. Screens show a message per [kind]; the details
/// never contain credentials or full stream URLs.
enum ProviderFailureKind {
  invalidInput,
  unauthorized,
  expired,
  banned,
  network,
  timeout,
  rateLimited,
  server,
  badResponse,
  unsupported,
}

class ProviderFailure implements Exception {
  const ProviderFailure(this.kind, [this.detail = '']);

  final ProviderFailureKind kind;

  /// Short, safe technical note for diagnostics (no secrets).
  final String detail;

  /// The connection status this failure leads to.
  ConnectionStatus get status => switch (kind) {
        ProviderFailureKind.invalidInput => ConnectionStatus.invalidConfiguration,
        ProviderFailureKind.unauthorized => ConnectionStatus.unauthorized,
        ProviderFailureKind.banned => ConnectionStatus.unauthorized,
        ProviderFailureKind.expired => ConnectionStatus.expired,
        ProviderFailureKind.unsupported => ConnectionStatus.invalidConfiguration,
        _ => ConnectionStatus.temporarilyUnavailable,
      };

  /// Worth an automatic retry with backoff.
  bool get isRetryable =>
      kind == ProviderFailureKind.network ||
      kind == ProviderFailureKind.timeout ||
      kind == ProviderFailureKind.server ||
      kind == ProviderFailureKind.rateLimited;

  @override
  String toString() =>
      detail.isEmpty ? 'ProviderFailure(${kind.name})' : 'ProviderFailure(${kind.name}: $detail)';
}

/// What the user typed to connect a panel. Kept in secure storage on the device
/// (step 5.5); [toString] never prints secrets.
sealed class ProviderCredentials {
  const ProviderCredentials();

  ProviderKind get kind;

  /// Instant local check before any network call ("connect in seconds", step 1).
  /// Returns field → problem; empty = looks valid.
  Map<String, ProviderInputError> validate();

  /// Label safe to show/log, e.g. the host name.
  String get safeLabel;

  Map<String, String> toStorage();

  static ProviderCredentials? fromStorage(Map<String, String> m) {
    switch (ProviderKind.fromKey(m['kind'])) {
      case ProviderKind.xtream:
        return XtreamCredentials(
          server: m['server'] ?? '',
          username: m['username'] ?? '',
          password: m['password'] ?? '',
        );
      case ProviderKind.m3u:
        return M3uCredentials(url: m['url'] ?? '', epgUrl: m['epgUrl']);
      case ProviderKind.stalker:
        return StalkerCredentials(portal: m['portal'] ?? '', mac: m['mac'] ?? '');
      case null:
        return null;
    }
  }

  @override
  String toString() => '${kind.name}($safeLabel)';
}

enum ProviderInputError { required, invalidUrl, invalidMac }

/// Normalises what users paste: adds http:// when missing, trims spaces and a
/// trailing slash, drops a pasted `player_api.php…` / `get.php…` tail.
Uri? parsePanelUrl(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return null;
  if (!s.contains('://')) s = 'http://$s';
  final u = Uri.tryParse(s);
  if (u == null || !(u.scheme == 'http' || u.scheme == 'https') || u.host.isEmpty) {
    return null;
  }
  var path = u.path;
  for (final tail in const ['/player_api.php', '/get.php', '/xmltv.php', '/panel_api.php']) {
    final i = path.indexOf(tail);
    if (i >= 0) path = path.substring(0, i);
  }
  while (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  return Uri(scheme: u.scheme, host: u.host, port: u.hasPort ? u.port : null, path: path);
}

/// An Xtream panel's playlist link (`…/get.php?username=…&password=…`) holds
/// a full Xtream login. Many panels refuse the playlist download (HTTP 884)
/// while the Xtream API works, so the app can connect the same line that way.
XtreamCredentials? xtreamFromPlaylistUrl(String raw) {
  final s = raw.trim();
  final u = Uri.tryParse(s.contains('://') ? s : 'http://$s');
  if (u == null || u.host.isEmpty || !u.path.toLowerCase().endsWith('/get.php')) return null;
  final user = u.queryParameters['username'] ?? '';
  final pass = u.queryParameters['password'] ?? '';
  if (user.isEmpty || pass.isEmpty) return null;
  final base = u.path.substring(0, u.path.length - '/get.php'.length);
  return XtreamCredentials(
    server: Uri(scheme: u.scheme, host: u.host, port: u.hasPort ? u.port : null, path: base).toString(),
    username: user,
    password: pass,
  );
}

class XtreamCredentials extends ProviderCredentials {
  const XtreamCredentials({required this.server, required this.username, required this.password});

  final String server;
  final String username;
  final String password;

  @override
  ProviderKind get kind => ProviderKind.xtream;

  Uri? get baseUri => parsePanelUrl(server);

  @override
  Map<String, ProviderInputError> validate() => {
        if (server.trim().isEmpty)
          'server': ProviderInputError.required
        else if (baseUri == null)
          'server': ProviderInputError.invalidUrl,
        if (username.trim().isEmpty) 'username': ProviderInputError.required,
        if (password.isEmpty) 'password': ProviderInputError.required,
      };

  @override
  String get safeLabel => baseUri?.host ?? 'xtream';

  @override
  Map<String, String> toStorage() =>
      {'kind': kind.name, 'server': server, 'username': username, 'password': password};
}

class M3uCredentials extends ProviderCredentials {
  const M3uCredentials({required this.url, this.epgUrl});

  final String url;
  final String? epgUrl;

  @override
  ProviderKind get kind => ProviderKind.m3u;

  Uri? get playlistUri {
    final s = url.trim();
    if (s.isEmpty) return null;
    final u = Uri.tryParse(s.contains('://') ? s : 'http://$s');
    if (u == null || !(u.scheme == 'http' || u.scheme == 'https') || u.host.isEmpty) {
      return null;
    }
    return u;
  }

  @override
  Map<String, ProviderInputError> validate() => {
        if (url.trim().isEmpty)
          'url': ProviderInputError.required
        else if (playlistUri == null)
          'url': ProviderInputError.invalidUrl,
        if ((epgUrl ?? '').trim().isNotEmpty && Uri.tryParse(epgUrl!.trim())?.host.isEmpty != false)
          'epgUrl': ProviderInputError.invalidUrl,
      };

  @override
  String get safeLabel => playlistUri?.host ?? 'm3u';

  @override
  Map<String, String> toStorage() =>
      {'kind': kind.name, 'url': url, 'epgUrl': ?epgUrl};
}

class StalkerCredentials extends ProviderCredentials {
  const StalkerCredentials({required this.portal, required this.mac});

  final String portal;
  final String mac;

  @override
  ProviderKind get kind => ProviderKind.stalker;

  Uri? get portalUri => parsePanelUrl(portal);

  /// `00:1a:79:ab:cd:ef` / `00-1A-79-AB-CD-EF` / `001A79ABCDEF` → `00:1A:79:AB:CD:EF`.
  String? get normalizedMac {
    final hex = mac.replaceAll(RegExp(r'[^0-9a-fA-F]'), '').toUpperCase();
    if (hex.length != 12) return null;
    if (RegExp(r'[^0-9a-fA-F:\-\s.]').hasMatch(mac.trim())) return null;
    return [for (var i = 0; i < 12; i += 2) hex.substring(i, i + 2)].join(':');
  }

  @override
  Map<String, ProviderInputError> validate() => {
        if (portal.trim().isEmpty)
          'portal': ProviderInputError.required
        else if (portalUri == null)
          'portal': ProviderInputError.invalidUrl,
        if (mac.trim().isEmpty)
          'mac': ProviderInputError.required
        else if (normalizedMac == null)
          'mac': ProviderInputError.invalidMac,
      };

  @override
  String get safeLabel => portalUri?.host ?? 'stalker';

  @override
  Map<String, String> toStorage() => {'kind': kind.name, 'portal': portal, 'mac': mac};
}

/// Account state reported by the panel at login.
class ProviderAccount {
  const ProviderAccount({
    required this.status,
    this.expiresAt,
    this.isTrial = false,
    this.maxConnections,
    this.activeConnections,
    this.allowedOutputFormats = const [],
    this.serverTimezone,
    this.message,
  });

  final ConnectionStatus status;

  /// Null = no expiry given (unlimited or unknown).
  final DateTime? expiresAt;
  final bool isTrial;

  /// Streams the account may play at once (usually 1: stop the old player first).
  final int? maxConnections;
  final int? activeConnections;

  /// Xtream: e.g. ["m3u8","ts"]. Empty = unknown (any).
  final List<String> allowedOutputFormats;
  final String? serverTimezone;

  /// Panel's own message (e.g. Stalker "account blocked"), safe to show.
  final String? message;

  /// Expires within [window] (for a "renew soon" hint).
  bool expiresSoon(DateTime now, {Duration window = const Duration(days: 3)}) =>
      expiresAt != null && expiresAt!.isAfter(now) && expiresAt!.difference(now) <= window;
}

/// What a protocol can do, so screens hide what a panel can't offer.
class ProviderCapabilities {
  const ProviderCapabilities({
    this.live = true,
    this.movies = false,
    this.series = false,
    this.epg = false,
    this.catchup = false,
    this.incrementalByAdded = false,
    this.linksExpire = false,
  });

  final bool live;
  final bool movies;
  final bool series;
  final bool epg;
  final bool catchup;

  /// Items carry an `added` time → cheap "what's new" sync (Phase 6).
  final bool incrementalByAdded;

  /// Stream links are short-lived (Stalker create_link) → resolve right before play.
  final bool linksExpire;
}

/// Where a playable item lives on the panel. Turned into a URL only at play
/// time ([ProviderAdapter.resolveStream]) so URLs with credentials are never
/// stored, synced or logged.
class StreamRef {
  const StreamRef({required this.kind, required this.id, this.extension, this.command});

  final MediaKind kind;
  final String id;

  /// Container (mp4/mkv/ts …) when the panel gives one.
  final String? extension;

  /// Protocol-specific play command (Stalker `cmd`, M3U direct URL).
  final String? command;
}

/// A resolved, ready-to-play stream. [url] contains credentials: hand it to the
/// player only — never log, store or send it anywhere.
class ResolvedStream {
  const ResolvedStream({required this.url, this.headers = const {}});

  final Uri url;
  final Map<String, String> headers;

  @override
  String toString() => 'ResolvedStream(${url.host})';
}

class ProviderCategory {
  const ProviderCategory({required this.id, required this.name, this.parentId, this.adult = false});

  final String id;
  final String name;
  final String? parentId;

  /// The panel marks it adult (Stalker `censored`). Name keywords are
  /// checked too (AdultClassifier) when the catalog is synced.
  final bool adult;
}

class ProviderChannel {
  const ProviderChannel({
    required this.id,
    required this.name,
    required this.stream,
    this.number,
    this.logoUrl,
    this.categoryId,
    this.epgId,
    this.catchupDays = 0,
    this.addedSec,
    this.adult = false,
  });

  final String id;
  final String name;
  final StreamRef stream;
  final int? number;
  final String? logoUrl;
  final String? categoryId;

  /// EPG channel id (Xtream `epg_channel_id`, M3U `tvg-id`).
  final String? epgId;
  final int catchupDays;
  final int? addedSec;

  /// The panel marks it adult (Xtream `is_adult`, Stalker `censored`).
  final bool adult;
}

class ProviderMovie {
  const ProviderMovie({
    required this.id,
    required this.name,
    required this.stream,
    this.posterUrl,
    this.rating,
    this.year,
    this.categoryId,
    this.addedSec,
    this.tmdbId,
    this.adult = false,
  });

  final String id;
  final String name;
  final StreamRef stream;
  final String? posterUrl;
  final double? rating;
  final int? year;
  final String? categoryId;
  final int? addedSec;
  final int? tmdbId;

  /// The panel marks it adult (Xtream `is_adult`, Stalker `censored`).
  final bool adult;
}

class ProviderSeries {
  const ProviderSeries({
    required this.id,
    required this.name,
    this.posterUrl,
    this.backdropUrl,
    this.plot,
    this.genres = const [],
    this.rating,
    this.year,
    this.categoryId,
    this.addedSec,
    this.tmdbId,
    this.adult = false,
  });

  final String id;
  final String name;
  final String? posterUrl;
  final String? backdropUrl;
  final String? plot;
  final List<String> genres;
  final double? rating;
  final int? year;
  final String? categoryId;

  /// Last change on the panel (Xtream `last_modified`).
  final int? addedSec;
  final int? tmdbId;

  /// The panel marks it adult (Xtream `is_adult`, Stalker `censored`).
  final bool adult;
}

class ProviderEpisode {
  const ProviderEpisode({
    required this.id,
    required this.seriesId,
    required this.season,
    required this.number,
    required this.title,
    required this.stream,
    this.durationSec,
    this.plot,
    this.stillUrl,
  });

  final String id;
  final String seriesId;
  final int season;
  final int number;
  final String title;
  final StreamRef stream;
  final int? durationSec;
  final String? plot;
  final String? stillUrl;
}

/// Details for one movie (opened on the details screen).
class ProviderMovieDetails {
  const ProviderMovieDetails({
    required this.movie,
    this.plot,
    this.genres = const [],
    this.cast,
    this.director,
    this.durationSec,
    this.backdropUrl,
    this.trailerYoutubeId,
  });

  final ProviderMovie movie;
  final String? plot;
  final List<String> genres;
  final String? cast;
  final String? director;
  final int? durationSec;
  final String? backdropUrl;
  final String? trailerYoutubeId;
}

/// Details for one series: its info plus episodes grouped by season number.
class ProviderSeriesDetails {
  const ProviderSeriesDetails({required this.series, required this.episodes});

  final ProviderSeries series;
  final Map<int, List<ProviderEpisode>> episodes;

  List<int> get seasonNumbers => episodes.keys.toList()..sort();
}

class EpgEntry {
  const EpgEntry({required this.title, required this.start, required this.end, this.description});

  final String title;
  final DateTime start;
  final DateTime end;
  final String? description;

  bool isOnAt(DateTime t) => !t.isBefore(start) && t.isBefore(end);

  /// 0..1 progress at [t] (0 before start, 1 after end).
  double progressAt(DateTime t) {
    final total = end.difference(start).inSeconds;
    if (total <= 0) return 0;
    return (t.difference(start).inSeconds / total).clamp(0.0, 1.0);
  }
}
