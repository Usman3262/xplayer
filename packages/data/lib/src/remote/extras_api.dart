import 'package:domain/domain.dart';

import '../diag/diag.dart';
import 'api_client.dart';
import 'api_exception.dart';
import 'auth_models.dart' show unwrapListData;

/// Backend additions for the TV client list of 16 Oct (App-Backend
/// `claude/tv-handoff-2026-10-16`). Every call treats 404 as "this backend
/// does not have it yet" and returns null / empty, so the app keeps working
/// against older deployments.
bool _missing(Object e) => e is ApiException && e.statusCode == 404;

String? _text(Object? v) {
  if (v == null) return null;
  final t = '$v'.trim();
  return t.isEmpty ? null : t;
}

/// One actor from TMDB (backend `castPhotos`, client 23 Oct).
class CastPhotoDto {
  const CastPhotoDto({required this.name, this.photoUrl});
  final String name;
  final String? photoUrl;

  static List<CastPhotoDto> listFrom(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final e in raw)
        if (e is Map && (e['name'] ?? '').toString().trim().isNotEmpty)
          CastPhotoDto(
            name: e['name'].toString().trim(),
            photoUrl: (e['photoUrl'] is String && (e['photoUrl'] as String).isNotEmpty) ? e['photoUrl'] as String : null,
          ),
    ];
  }
}

/// `GET /catalog/vod/:id/info` (provider get_vod_info).
class VodInfoDto {
  const VodInfoDto({
    required this.vodId,
    this.plot,
    this.cast,
    this.director,
    this.genres = const [],
    this.releaseDate,
    this.year,
    this.durationSec,
    this.rating,
    this.backdropUrl,
    this.trailer,
    this.castPhotos = const [],
  });

  final String vodId;
  /// TMDB cast with photos; empty when the server has none.
  final List<CastPhotoDto> castPhotos;
  final String? plot;
  final String? cast;
  final String? director;
  final List<String> genres;
  final String? releaseDate;
  final String? year;
  final int? durationSec;
  final String? rating;
  final String? backdropUrl;
  final String? trailer;

  factory VodInfoDto.fromJson(Map<String, dynamic> j) {
    // Prefer clock / alternate fields when backends mis-map Xtream minutes
    // into durationSec (details then showed "2m" for a 2h film).
    final parsed = parseDurationToSeconds(
          j['duration'] ?? j['runtime'] ?? j['duration_secs'],
        ) ??
        parseDurationToSeconds(j['durationSec']);
    return VodInfoDto(
      vodId: '${j['vodId'] ?? ''}',
      plot: _text(j['plot']),
      cast: _text(j['cast']),
      director: _text(j['director']),
      genres: [
        for (final g in (j['genres'] as List? ?? const [])) '$g',
      ],
      releaseDate: _text(j['releaseDate']),
      year: _text(j['year']),
      durationSec: parsed,
      rating: _text(j['rating']),
      backdropUrl: _text(j['backdropUrl']),
      trailer: _text(j['trailer']),
      castPhotos: CastPhotoDto.listFrom(j['castPhotos']),
    );
  }
}

/// One programme from `GET /catalog/live/:id/epg`.
class EpgProgramDto {
  const EpgProgramDto({
    required this.title,
    required this.startAt,
    required this.endAt,
    this.description,
  });

  final String title;
  final String? description;
  final DateTime startAt;
  final DateTime endAt;

  bool isOnAt(DateTime t) => !t.isBefore(startAt) && t.isBefore(endAt);

  static EpgProgramDto? tryParse(Map<String, dynamic> j) {
    final title = _text(j['title']);
    final s = DateTime.tryParse('${j['startAt'] ?? ''}');
    final e = DateTime.tryParse('${j['endAt'] ?? ''}');
    if (title == null || s == null || e == null) return null;
    return EpgProgramDto(
      title: title,
      description: _text(j['description']),
      startAt: s.toLocal(),
      endAt: e.toLocal(),
    );
  }
}

/// `GET /profiles/:id/reminders` row.
class ReminderDto {
  const ReminderDto({
    required this.contentType,
    required this.streamId,
    this.seriesId,
    this.title,
    this.posterUrl,
    this.programTitle,
    this.startsAt,
  });

  final String contentType;
  final String streamId;
  final String? seriesId;
  final String? title;
  final String? posterUrl;
  final String? programTitle;
  final DateTime? startsAt;

  factory ReminderDto.fromJson(Map<String, dynamic> j) => ReminderDto(
        contentType: '${j['contentType'] ?? 'vod'}',
        streamId: '${j['streamId'] ?? ''}',
        seriesId: _text(j['seriesId']),
        title: _text(j['title']),
        posterUrl: _text(j['posterUrl']),
        programTitle: _text(j['programTitle']),
        startsAt: DateTime.tryParse('${j['startsAt'] ?? ''}')?.toLocal(),
      );
}

/// Totals for one section (`GET /catalog/counts`).
class SectionCountsDto {
  const SectionCountsDto({required this.total, required this.byCategory});

  final int total;
  final Map<String, int> byCategory;

  factory SectionCountsDto.fromJson(Object? raw) {
    final j = raw is Map ? raw : const {};
    final by = <String, int>{};
    final m = j['byCategory'];
    if (m is Map) {
      m.forEach((k, v) {
        final n = v is num ? v.toInt() : int.tryParse('$v');
        if (n != null) by['$k'] = n;
      });
    }
    final t = j['total'];
    return SectionCountsDto(
      total: t is num ? t.toInt() : int.tryParse('$t') ?? 0,
      byCategory: by,
    );
  }
}

/// Real totals of the user's package, per section and per package.
class CatalogCountsDto {
  const CatalogCountsDto({
    required this.live,
    required this.vod,
    required this.series,
  });

  final SectionCountsDto live;
  final SectionCountsDto vod;
  final SectionCountsDto series;

  factory CatalogCountsDto.fromJson(Map<String, dynamic> j) => CatalogCountsDto(
        live: SectionCountsDto.fromJson(j['live']),
        vod: SectionCountsDto.fromJson(j['vod']),
        series: SectionCountsDto.fromJson(j['series']),
      );
}

/// Storage limit for downloads, all of the customer's devices together.
class DownloadQuotaDto {
  const DownloadQuotaDto({
    required this.limitBytes,
    required this.usedBytes,
    required this.remainingBytes,
  });

  final int limitBytes;
  final int usedBytes;
  final int remainingBytes;

  static DownloadQuotaDto? tryParse(Object? raw) {
    if (raw is! Map) return null;
    int? n(Object? v) => v is num ? v.toInt() : int.tryParse('$v');
    final limit = n(raw['limitBytes']);
    final used = n(raw['usedBytes']);
    if (limit == null || used == null) return null;
    return DownloadQuotaDto(
      limitBytes: limit,
      usedBytes: used,
      remainingBytes: n(raw['remainingBytes']) ?? (limit - used),
    );
  }
}

class ExtrasApi {
  ExtrasApi(this._client);

  final ApiClient _client;

  /// Package catalog version (`GET /catalog/version`). The backend bumps it
  /// when a package changes in the Control Panel or a catalog refresh runs.
  /// Null when unavailable.
  Future<String?> catalogVersion() async {
    try {
      final data = await _client.get('/catalog/version', auth: true);
      final v = data?['version'] ?? data?['etag'];
      return v == null ? null : '$v';
    } catch (_) {
      return null;
    }
  }

  /// Null when this backend has no counts route (old server) or it failed.
  Future<CatalogCountsDto?> catalogCounts() async {
    try {
      final data = await _client.get('/catalog/counts', auth: true);
      return data == null ? null : CatalogCountsDto.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  /// Saved package order (category ids) of [section] = live | vod | series.
  /// Null = no server route; empty = provider order.
  Future<List<String>?> categoryOrder(String profileId, String section) async {
    try {
      final data = await _client.get(
        '/profiles/$profileId/category-order/$section',
        auth: true,
      );
      final ids = data?['categoryIds'];
      return ids is List ? [for (final e in ids) '$e'] : const [];
    } catch (e) {
      if (_missing(e)) return null;
      rethrow;
    }
  }

  /// True when the server stored it.
  Future<bool> saveCategoryOrder(
    String profileId,
    String section,
    List<String> categoryIds,
  ) async {
    try {
      await _client.put(
        '/profiles/$profileId/category-order/$section',
        auth: true,
        body: {'categoryIds': categoryIds},
      );
      return true;
    } catch (e) {
      if (_missing(e)) return false;
      rethrow;
    }
  }

  /// Null when the backend has no quota route.
  Future<DownloadQuotaDto?> downloadQuota() async {
    try {
      final data = await _client.get('/downloads/quota', auth: true);
      return DownloadQuotaDto.tryParse(data);
    } catch (_) {
      return null;
    }
  }

  Future<VodInfoDto?> vodInfo(String vodId) async {
    try {
      final data = await _client.get('/catalog/vod/$vodId/info', auth: true);
      return data == null ? null : VodInfoDto.fromJson(data);
    } catch (e) {
      if (_missing(e)) return null;
      rethrow;
    }
  }

  /// Now / next programmes; empty when the channel has no guide or the
  /// backend has no EPG route.
  /// This is TV-guide data (title + time), not player lineups.
  Future<List<EpgProgramDto>> liveEpg(String streamId, {int limit = 4}) async {
    try {
      final data = await _client.get(
        '/catalog/live/$streamId/epg',
        auth: true,
        query: {'limit': '$limit'},
      );
      final list = [
        for (final row in unwrapListData(data))
          if (EpgProgramDto.tryParse(row) case final p?) p,
      ];
      final sample = list
          .take(2)
          .map((p) => '"${p.title}"@${p.startAt.toIso8601String()}')
          .join(' | ');
      Diag.dev(
        'SPORTS_DATA liveEpg streamId=$streamId count=${list.length} '
        'kind=epg_guide_NOT_lineups sample=$sample',
      );
      return list;
    } catch (e) {
      if (_missing(e)) {
        Diag.dev(
          'SPORTS_DATA liveEpg streamId=$streamId missing/404 '
          '(no EPG route or empty guide)',
        );
        return const [];
      }
      Diag.dev(
        'SPORTS_DATA liveEpg FAILED streamId=$streamId '
        'type=${e.runtimeType} err=$e',
      );
      rethrow;
    }
  }

  /// Null = this backend has no reminders API (keep them on the device).
  Future<List<ReminderDto>?> reminders(String profileId) async {
    try {
      final data =
          await _client.get('/profiles/$profileId/reminders', auth: true);
      return unwrapListData(data).map(ReminderDto.fromJson).toList();
    } catch (e) {
      if (_missing(e)) return null;
      rethrow;
    }
  }

  /// False when the backend has no reminders API.
  Future<bool> addReminder({
    required String profileId,
    required String contentType,
    required String streamId,
    String? seriesId,
    String? title,
    String? posterUrl,
    String? programTitle,
    DateTime? startsAt,
  }) async {
    try {
      await _client.post(
        '/profiles/$profileId/reminders',
        body: {
          'contentType': contentType,
          'streamId': streamId,
          'seriesId': seriesId,
          'title': title,
          'posterUrl': posterUrl,
          'programTitle': programTitle,
          'startsAt': startsAt?.toUtc().toIso8601String(),
        },
        auth: true,
      );
      return true;
    } catch (e) {
      if (_missing(e)) return false;
      rethrow;
    }
  }

  Future<bool> removeReminder({
    required String profileId,
    required String contentType,
    required String streamId,
    DateTime? startsAt,
  }) async {
    final q = startsAt == null
        ? ''
        : '?startsAt=${Uri.encodeQueryComponent(startsAt.toUtc().toIso8601String())}';
    try {
      await _client.delete(
        '/profiles/$profileId/reminders/$contentType/$streamId$q',
        auth: true,
      );
      return true;
    } catch (e) {
      if (_missing(e)) return false;
      rethrow;
    }
  }
}
