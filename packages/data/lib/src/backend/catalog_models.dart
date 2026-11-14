// Global-catalog payloads: `search_catalog` hits and `metadata-tmdb`
// resolve/season replies. Artwork is stored as TMDB paths ("/abc.jpg");
// build URLs with [ArtworkUrls] using the `metadata.*` config settings.

import '../remote/json_read.dart';
import 'remote_config.dart';
import 'json_util.dart';

/// Builds artwork URLs from config (`metadata.image_base_url` + size + path).
/// Full https URLs (admin uploads) pass through unchanged.
class ArtworkUrls {
  const ArtworkUrls({
    this.baseUrl = 'https://image.tmdb.org/t/p',
    this.posterSize = 'w342',
    this.backdropSize = 'w1280',
  });

  factory ArtworkUrls.fromConfig(RemoteConfig c) => ArtworkUrls(
        baseUrl: c.stringSetting('metadata.image_base_url', 'https://image.tmdb.org/t/p'),
        posterSize: c.stringSetting('metadata.poster_size', 'w342'),
        backdropSize: c.stringSetting('metadata.backdrop_size', 'w1280'),
      );

  final String baseUrl;
  final String posterSize;
  final String backdropSize;

  String? poster(String? path) => _url(path, posterSize);
  String? backdrop(String? path) => _url(path, backdropSize);
  String? sized(String? path, String size) => _url(path, size);

  String? _url(String? path, String size) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    final p = path.startsWith('/') ? path : '/$path';
    return '$baseUrl/$size$p';
  }
}

enum CatalogKind { movie, series, live }

class CatalogSearchHit {
  const CatalogSearchHit({required this.kind, required this.id, required this.title, this.year, this.image, this.score = 0});
  final CatalogKind kind;
  final String id;
  final String title;
  final int? year;
  final String? image;
  final double score;

  static List<CatalogSearchHit> listFrom(Object? json) => [
        for (final j in (json is List ? json : const []).whereType<Map>().map(jsonMap))
          if (jsonStr(j['id']) != null && jsonStr(j['title']) != null)
            CatalogSearchHit(
              kind: jsonEnum(j['kind'], CatalogKind.values, CatalogKind.movie),
              id: jsonStr(j['id'])!,
              title: jsonStr(j['title'])!,
              year: jsonInt(j['year']),
              image: jsonStr(j['image']),
              score: jsonDouble(j['score']) ?? 0,
            ),
      ];
}

/// One `metadata-tmdb resolve` result (null entries = no confident match).
class TitleMetadata {
  const TitleMetadata({
    required this.kind,
    required this.id,
    required this.title,
    this.tmdbId,
    this.year,
    this.overview,
    this.posterPath,
    this.backdropPath,
    this.logoPath,
    this.rating,
    this.trailerYoutube,
  });

  final CatalogKind kind;
  final String id;
  final String title;
  final int? tmdbId;
  final int? year;
  final String? overview;
  final String? posterPath;
  final String? backdropPath;
  final String? logoPath;
  final double? rating;
  final String? trailerYoutube;

  static TitleMetadata? tryParse(Object? v) {
    final j = jsonMap(v);
    final id = jsonStr(j['id']);
    final title = jsonStr(j['title']);
    if (id == null || title == null) return null;
    return TitleMetadata(
      kind: jsonEnum(j['kind'], CatalogKind.values, CatalogKind.movie),
      id: id,
      title: title,
      tmdbId: jsonInt(j['tmdb_id']),
      year: jsonInt(j['year']),
      overview: jsonStr(j['overview']),
      posterPath: jsonStr(j['poster_path']),
      backdropPath: jsonStr(j['backdrop_path']),
      logoPath: jsonStr(j['logo_path']),
      rating: jsonDouble(j['rating']),
      trailerYoutube: jsonStr(j['trailer_youtube']),
    );
  }

  /// `{"results":[…]}` → same length as the request, null where unmatched.
  static List<TitleMetadata?> resolveReply(Object? json) =>
      (jsonMap(json)['results'] is List ? jsonMap(json)['results'] as List : const [])
          .map(tryParse)
          .toList();
}

/// A title to look up via `metadata-tmdb resolve`. Send [tmdbId] when the panel
/// provides one (fast, exact); otherwise the panel's raw name (+ year).
class MetadataQuery {
  const MetadataQuery({required this.kind, this.tmdbId, this.title, this.year})
      : assert(tmdbId != null || title != null);

  final CatalogKind kind;
  final int? tmdbId;
  final String? title;
  final int? year;

  /// Max items per `resolve` call (server limit).
  static const maxBatch = 25;

  Map<String, dynamic> toJson() => {
        'kind': kind == CatalogKind.series ? 'series' : 'movie',
        if (tmdbId != null) 'tmdb_id': tmdbId,
        if (tmdbId == null && title != null) 'title': title,
        if (year != null) 'year': year,
      };
}

class EpisodeMetadata {
  const EpisodeMetadata({required this.id, required this.number, this.name, this.overview, this.stillPath, this.airDate, this.runtimeMin});
  final String id;
  final int number;
  final String? name;
  final String? overview;
  final String? stillPath;
  final DateTime? airDate;
  final int? runtimeMin;

  /// `metadata-tmdb season` reply → episodes in order.
  static List<EpisodeMetadata> seasonReply(Object? json) => [
        for (final e in jsonMapList(jsonMap(json)['episodes']))
          if (jsonStr(e['id']) != null && jsonInt(e['episode_number']) != null)
            EpisodeMetadata(
              id: jsonStr(e['id'])!,
              number: jsonInt(e['episode_number'])!,
              name: jsonStr(e['name']),
              overview: jsonStr(e['overview']),
              stillPath: jsonStr(e['still_path']),
              airDate: jsonDate(e['air_date']),
              runtimeMin: jsonInt(e['runtime_min']),
            ),
      ]..sort((a, b) => a.number.compareTo(b.number));
}
