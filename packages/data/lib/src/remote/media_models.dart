import 'extras_api.dart' show CastPhotoDto;
import 'package:flutter/foundation.dart';

import 'auth_models.dart';
import 'json_read.dart';

class CatalogCategoryDto {
  const CatalogCategoryDto({
    required this.id,
    required this.name,
    this.isSports,
  });

  final String id;
  final String name;

  /// Live only: the backend's sports flag (operator list / name pattern).
  /// Null on older backends: callers fall back to the name rule.
  final bool? isSports;

  factory CatalogCategoryDto.fromJson(Map<String, dynamic> json) {
    final s = json['isSports'];
    return CatalogCategoryDto(
      id: '${json['id'] ?? ''}',
      name: jsonStr(json['name']) ?? 'Category',
      isSports: s is bool ? s : null,
    );
  }
}

class CatalogStreamDto {
  const CatalogStreamDto({
    required this.streamId,
    required this.name,
    this.rawName,
    this.resolution,
    this.posterUrl,
    this.categoryId,
    this.containerExtension,
    required this.contentType,
    this.epgChannelId,
    this.genres = const [],
    this.synopsis,
    this.year,
    this.rating,
    this.durationSec,
    this.added,
  });

  final String streamId;
  final String name;
  final String? rawName;
  final String? resolution;
  final String? posterUrl;
  final String? categoryId;
  final String? containerExtension;
  final String contentType;
  final String? epgChannelId;
  final List<String> genres;
  final String? synopsis;
  final String? year;
  final String? rating;
  final int? durationSec;

  /// Provider date added (unix s), newest-first lists (client 18 Oct #14).
  final int? added;

  factory CatalogStreamDto.fromJson(Map<String, dynamic> json) {
    final rawGenres = json['genres'];
    final genres = rawGenres is List
        ? rawGenres.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
        : const <String>[];
    return CatalogStreamDto(
      streamId: '${json['streamId'] ?? ''}',
      name: (jsonStr(json['name']))?.trim().isNotEmpty == true
          ? jsonStr(json['name'])!.trim()
          : '',
      rawName: jsonStr(json['rawName']),
      resolution: jsonStr(json['resolution']),
      posterUrl: jsonStr(json['posterUrl']),
      categoryId: json['categoryId']?.toString(),
      containerExtension: jsonStr(json['containerExtension']),
      contentType: jsonStr(json['contentType']) ?? 'vod',
      epgChannelId: json['epgChannelId']?.toString(),
      genres: genres,
      synopsis: jsonStr(json['synopsis']) ??
          jsonStr(json['plot']) ??
          jsonStr(json['description']) ??
          jsonStr(json['overview']),
      year: json['year']?.toString(),
      rating: json['rating']?.toString(),
      durationSec: (jsonDouble(json['durationSec']))?.toInt(),
      added: (jsonDouble(json['added']))?.toInt(),
    );
  }
}

class SeriesEpisodeDto {
  const SeriesEpisodeDto({
    required this.id,
    required this.title,
    this.containerExtension,
    this.episodeNum,
    this.durationSec,
    this.plot,
    this.stillUrl,
  });

  final String id;
  final String title;
  final String? containerExtension;
  final int? episodeNum;
  final int? durationSec;
  final String? plot;
  final String? stillUrl;

  factory SeriesEpisodeDto.fromJson(Map<String, dynamic> json) {
    return SeriesEpisodeDto(
      id: '${json['id'] ?? ''}',
      title: jsonStr(json['title']) ?? 'Episode',
      containerExtension: jsonStr(json['containerExtension']),
      episodeNum: (jsonDouble(json['episodeNum']))?.toInt(),
      durationSec: (jsonDouble(json['durationSec']))?.toInt() ??
          _durationSecsFromStill(json['stillUrl']),
      plot: jsonStr(json['plot']) ?? jsonStr(json['synopsis']),
      stillUrl: _stillImageUrl(json['stillUrl']),
    );
  }
}

String? _stillImageUrl(Object? raw) {
  if (raw == null) return null;
  if (raw is String) {
    final s = raw.trim();
    return s.isEmpty ? null : s;
  }
  if (raw is Map) {
    final m = Map<String, dynamic>.from(raw);
    for (final key in ['movie_image', 'stillUrl', 'url', 'image', 'poster']) {
      final v = m[key];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
  }
  return null;
}

int? _durationSecsFromStill(Object? raw) {
  if (raw is! Map) return null;
  final m = Map<String, dynamic>.from(raw);
  final secs = m['duration_secs'] ?? m['durationSec'];
  if (secs is num) return secs.toInt();
  return null;
}

class SeriesSeasonDto {
  const SeriesSeasonDto({
    required this.season,
    this.episodes = const [],
  });

  final String season;
  final List<SeriesEpisodeDto> episodes;

  factory SeriesSeasonDto.fromJson(Map<String, dynamic> json) {
    final raw = json['episodes'];
    final episodes = raw is List
        ? raw
            .whereType<Map>()
            .map((e) => SeriesEpisodeDto.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : const <SeriesEpisodeDto>[];
    return SeriesSeasonDto(
      season: '${json['season'] ?? '1'}',
      episodes: episodes,
    );
  }
}

class SeriesDetailDto {
  const SeriesDetailDto({
    required this.seriesId,
    required this.name,
    this.plot,
    this.posterUrl,
    this.backdropUrl,
    this.cast,
    this.seasons = const [],
    this.castPhotos = const [],
  });

  final String seriesId;
  /// TMDB cast with photos; empty when the server has none.
  final List<CastPhotoDto> castPhotos;
  final String name;
  final String? plot;
  /// Provider cast names (backend #16); null on older servers.
  final String? cast;
  final String? posterUrl;
  final String? backdropUrl;
  final List<SeriesSeasonDto> seasons;

  /// The episode's own still: by episode id, else by season + episode number.
  String? stillFor({String? episodeId, int? season, int? episode}) {
    if (episodeId != null && episodeId.isNotEmpty) {
      for (final s in seasons) {
        for (final e in s.episodes) {
          if (e.id == episodeId) return e.stillUrl;
        }
      }
    }
    if (season == null || episode == null) return null;
    for (final s in seasons) {
      if (int.tryParse(s.season) != season) continue;
      for (final e in s.episodes) {
        if (e.episodeNum == episode) return e.stillUrl;
      }
    }
    return null;
  }

  factory SeriesDetailDto.fromJson(Map<String, dynamic> json) {
    final raw = json['seasons'];
    final seasons = raw is List
        ? raw
            .whereType<Map>()
            .map((e) => SeriesSeasonDto.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : const <SeriesSeasonDto>[];
    return SeriesDetailDto(
      seriesId: '${json['seriesId'] ?? ''}',
      name: jsonStr(json['name']) ?? 'Series',
      plot: jsonStr(json['plot']),
      posterUrl: jsonStr(json['posterUrl']),
      backdropUrl: jsonStr(json['backdropUrl']),
      cast: jsonStr(json['cast']),
      seasons: seasons,
      castPhotos: CastPhotoDto.listFrom(json['castPhotos']),
    );
  }
}

/// `GET /v1/playback/active` — who holds the stream lease (takeover UI).
class PlaybackActiveDto {
  const PlaybackActiveDto({
    required this.active,
    this.deviceId,
    this.deviceName,
    this.startedAt,
    this.title,
    this.playbackId,
    this.contentType,
  });

  final bool active;
  final String? deviceId;
  final String? deviceName;
  final String? startedAt;
  final String? title;
  final String? playbackId;
  final String? contentType;

  factory PlaybackActiveDto.fromJson(Map<String, dynamic> json) {
    return PlaybackActiveDto(
      active: jsonBool(json['active']) ?? false,
      deviceId: jsonStr(json['deviceId']),
      deviceName: jsonStr(json['deviceName']),
      startedAt: jsonStr(json['startedAt']),
      title: jsonStr(json['title']),
      playbackId: jsonStr(json['playbackId']),
      contentType: jsonStr(json['contentType']),
    );
  }
}

/// `GET /v1/playback/lease` — Redis-backed Active/Inactive session status.
class PlaybackLeaseStatusDto {
  const PlaybackLeaseStatusDto({
    required this.status,
    required this.label,
    required this.active,
    required this.max,
    this.playback,
  });

  /// `"Active"` or `"Inactive"`.
  final String status;
  /// Compact badge e.g. `"1/1"` / `"0/1"`.
  final String label;
  final int active;
  final int max;
  final PlaybackLeaseActiveDto? playback;

  bool get isActive =>
      active > 0 || status.toLowerCase() == 'active';

  factory PlaybackLeaseStatusDto.fromJson(Map<String, dynamic> json) {
    final playbackRaw = json['playback'];
    return PlaybackLeaseStatusDto(
      status: jsonStr(json['status']) ?? 'Inactive',
      label: jsonStr(json['label']) ?? '0/1',
      active: (jsonDouble(json['active']))?.toInt() ?? 0,
      max: (jsonDouble(json['max']))?.toInt() ?? 1,
      playback: playbackRaw is Map<String, dynamic>
          ? PlaybackLeaseActiveDto.fromJson(playbackRaw)
          : null,
    );
  }
}

class PlaybackLeaseActiveDto {
  const PlaybackLeaseActiveDto({
    required this.playbackId,
    required this.deviceId,
    required this.contentType,
    required this.streamId,
    this.startedAt,
    this.expiresAt,
  });

  final String playbackId;
  final String deviceId;
  final String contentType;
  final String streamId;
  final String? startedAt;
  final String? expiresAt;

  factory PlaybackLeaseActiveDto.fromJson(Map<String, dynamic> json) {
    return PlaybackLeaseActiveDto(
      playbackId: jsonStr(json['playbackId']) ?? '',
      deviceId: jsonStr(json['deviceId']) ?? '',
      contentType: jsonStr(json['contentType']) ?? '',
      streamId: '${json['streamId'] ?? ''}',
      startedAt: jsonStr(json['startedAt']),
      expiresAt: jsonStr(json['expiresAt']),
    );
  }
}

class PlaybackSessionDto {
  const PlaybackSessionDto({
    required this.playbackId,
    required this.contentType,
    required this.streamId,
    this.container,
    required this.playUrl,
    this.host,
    this.expiresAt,
    this.leaseTtlSec = 60,
    this.heartbeatIntervalSec,
    this.urlContinuity,
    this.alternatePlayUrls = const [],
    this.providerAuthUrl,
    this.abrAvailable,
    this.status,
  });

  final String playbackId;
  final String contentType;
  final String streamId;
  final String? container;
  final String playUrl;
  final String? host;
  final String? expiresAt;
  final int leaseTtlSec;
  final int? heartbeatIntervalSec;
  final String? urlContinuity;

  /// Backend-approved fallback URLs for the same lease (other scheme), tried
  /// in order only when [playUrl] fails to open.
  final List<String> alternatePlayUrls;

  /// Backend-provided provider login (player_api.php) for the same line, called
  /// from the device before streaming like a standard Xtream player.
  final String? providerAuthUrl;
  final bool? abrAvailable;
  final String? status;

  factory PlaybackSessionDto.fromJson(Map<String, dynamic> json) {
    return PlaybackSessionDto(
      playbackId: jsonStr(json['playbackId']) ?? '',
      contentType: jsonStr(json['contentType']) ?? '',
      streamId: '${json['streamId'] ?? ''}',
      container: jsonStr(json['container']),
      playUrl: jsonStr(json['playUrl']) ?? '',
      host: jsonStr(json['host']),
      expiresAt: jsonStr(json['expiresAt']),
      leaseTtlSec: (jsonDouble(json['leaseTtlSec']))?.toInt() ?? 60,
      heartbeatIntervalSec: (jsonDouble(json['heartbeatIntervalSec']))?.toInt(),
      urlContinuity: jsonStr(json['urlContinuity']),
      alternatePlayUrls: (json['alternatePlayUrls'] as List?)
              ?.whereType<String>()
              .where((u) => u.isNotEmpty)
              .toList() ??
          const [],
      providerAuthUrl: jsonStr(json['providerAuthUrl']),
      abrAvailable: jsonBool(json['abrAvailable']),
      status: jsonStr(json['status']),
    );
  }
}

class ProfileDto {
  const ProfileDto({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.isKids = false,
    this.sortOrder = 0,
    this.pinLocked = false,
  });

  final String id;
  final String name;
  final String? avatarUrl;
  final bool isKids;
  final int sortOrder;

  /// Needs the account Kids PIN to open (server, client 23 Oct #3).
  final bool pinLocked;

  factory ProfileDto.fromJson(Map<String, dynamic> json) {
    return ProfileDto(
      id: jsonStr(json['id']) ?? '',
      name: jsonStr(json['name']) ?? 'Profile',
      avatarUrl: jsonStr(json['avatarUrl']),
      isKids: jsonBool(json['isKids']) ?? false,
      sortOrder: (jsonDouble(json['sortOrder']))?.toInt() ?? 0,
      pinLocked: jsonBool(json['pinLocked']) ?? false,
    );
  }
}

class ContinueWatchingDto {
  const ContinueWatchingDto({
    required this.contentType,
    required this.streamId,
    this.seriesId,
    this.episodeId,
    required this.title,
    this.posterUrl,
    this.stillUrl,
    this.backdropUrl,
    this.seasonNumber,
    this.episodeNumber,
    this.containerExtension,
    this.positionSec = 0,
    this.durationSec = 0,
    this.updatedAt,
  });

  final String contentType;
  final String streamId;
  final String? seriesId;
  final String? episodeId;
  final String title;
  final String? posterUrl;

  /// That episode's own still (backend content sync, client 1 Nov #7).
  final String? stillUrl;

  /// The movie's scene image (backend content sync).
  final String? backdropUrl;
  final int? seasonNumber;
  final int? episodeNumber;
  final String? containerExtension;
  final int positionSec;
  final int durationSec;
  final String? updatedAt;

  factory ContinueWatchingDto.fromJson(Map<String, dynamic> json) {
    return ContinueWatchingDto(
      contentType: jsonStr(json['contentType']) ?? 'vod',
      streamId: '${json['streamId'] ?? ''}',
      seriesId: json['seriesId']?.toString(),
      episodeId: json['episodeId']?.toString(),
      title: (jsonStr(json['title']))?.trim().isNotEmpty == true
          ? jsonStr(json['title'])!.trim()
          : '',
      posterUrl: jsonStr(json['posterUrl']),
      stillUrl: jsonStr(json['stillUrl']),
      backdropUrl: jsonStr(json['backdropUrl']),
      seasonNumber: jsonDouble(json['seasonNumber'] ?? json['season'])?.toInt(),
      episodeNumber:
          jsonDouble(json['episodeNumber'] ?? json['episodeNum'])?.toInt(),
      containerExtension: jsonStr(json['containerExtension']),
      positionSec: (jsonDouble(json['positionSec']))?.toInt() ?? 0,
      durationSec: (jsonDouble(json['durationSec']))?.toInt() ?? 0,
      updatedAt: jsonStr(json['updatedAt']),
    );
  }
}

class ProfileLibraryItemDto {
  const ProfileLibraryItemDto({
    required this.contentType,
    required this.streamId,
    this.seriesId,
    required this.title,
    this.posterUrl,
    this.createdAt,
    this.categoryId,
  });

  final String contentType;
  final String streamId;
  final String? seriesId;
  final String title;
  final String? posterUrl;
  final String? createdAt;

  /// Channel category saved by the server (favourites, backend #19): keeps
  /// Live TV and Sports favourites apart on every device.
  final String? categoryId;

  factory ProfileLibraryItemDto.fromJson(Map<String, dynamic> json) {
    return ProfileLibraryItemDto(
      contentType: jsonStr(json['contentType']) ?? 'vod',
      streamId: '${json['streamId'] ?? ''}',
      seriesId: json['seriesId']?.toString(),
      title: (jsonStr(json['title']))?.trim().isNotEmpty == true
          ? jsonStr(json['title'])!.trim()
          : '',
      posterUrl: jsonStr(json['posterUrl']),
      createdAt: jsonStr(json['createdAt']),
      categoryId: json['categoryId']?.toString(),
    );
  }
}

List<CatalogCategoryDto> parseCategories(Map<String, dynamic>? data) =>
    unwrapListData(data).map(CatalogCategoryDto.fromJson).toList();

List<CatalogStreamDto> parseStreams(Map<String, dynamic>? data) =>
    unwrapListData(data).map(CatalogStreamDto.fromJson).toList();

/// Offloads large list mapping when [data] has many items (home/catalog rails).
Future<List<CatalogCategoryDto>> parseCategoriesAsync(
  Map<String, dynamic>? data,
) async {
  final rows = unwrapListData(data);
  if (rows.length < 12) return parseCategories(data);
  return compute(_parseCategoriesIsolate, data);
}

Future<List<CatalogStreamDto>> parseStreamsAsync(
  Map<String, dynamic>? data,
) async {
  final rows = unwrapListData(data);
  if (rows.length < 8) return parseStreams(data);
  return compute(_parseStreamsIsolate, data);
}

Future<SeriesDetailDto> parseSeriesDetailAsync(Map<String, dynamic> data) {
  return compute(_parseSeriesDetailIsolate, data);
}

List<CatalogCategoryDto> _parseCategoriesIsolate(Map<String, dynamic>? data) =>
    parseCategories(data);

List<CatalogStreamDto> _parseStreamsIsolate(Map<String, dynamic>? data) =>
    parseStreams(data);

SeriesDetailDto _parseSeriesDetailIsolate(Map<String, dynamic> data) =>
    SeriesDetailDto.fromJson(data);

class SubscriptionDto {
  const SubscriptionDto({
    required this.id,
    required this.packageName,
    this.packageCode,
    this.bouquetId,
    this.status = 'ACTIVE',
    this.renewsAt,
    this.startsAt,
    this.maxDevices,
    this.maxConcurrentStreams,
    this.features = const [],
    this.sportsEnabled = false,
  });

  final String id;
  final String packageName;
  final String? packageCode;
  final String? bouquetId;
  final String status;
  final String? renewsAt;
  final String? startsAt;
  final int? maxDevices;
  final int? maxConcurrentStreams;
  final List<String> features;
  final bool sportsEnabled;

  factory SubscriptionDto.fromJson(Map<String, dynamic> json) {
    final raw = json['features'];
    final features = raw is List
        ? raw.map((e) => e.toString()).toList()
        : const <String>[];
    return SubscriptionDto(
      id: '${json['id'] ?? ''}',
      packageName: jsonStr(json['packageName']) ?? 'Package',
      packageCode: jsonStr(json['packageCode']),
      bouquetId: json['bouquetId']?.toString(),
      status: jsonStr(json['status']) ?? 'ACTIVE',
      renewsAt: jsonStr(json['renewsAt']),
      startsAt: jsonStr(json['startsAt']),
      maxDevices: (jsonDouble(json['maxDevices']))?.toInt(),
      maxConcurrentStreams: (jsonDouble(json['maxConcurrentStreams']))?.toInt(),
      features: features,
      sportsEnabled: jsonBool(json['sportsEnabled']) ??
          features.map((e) => e.toLowerCase()).contains('sports'),
    );
  }
}

class SportsFeatureDto {
  const SportsFeatureDto({required this.enabled});

  final bool enabled;

  factory SportsFeatureDto.fromJson(Map<String, dynamic> json) {
    return SportsFeatureDto(enabled: jsonBool(json['enabled']) ?? false);
  }
}

/// Weekly Top 10 chosen on the server (`GET /catalog/top10`, backend #135):
/// the same lists on every device all week, changed every Friday 00:00
/// Riyadh time. Items are ranked (1 = first) and shaped like the catalog lists.
class WeeklyTop10Dto {
  const WeeklyTop10Dto({
    required this.movies,
    required this.series,
    this.week,
    this.nextUpdateAt,
  });

  final List<CatalogStreamDto> movies;
  final List<CatalogStreamDto> series;
  final String? week;

  /// When the next list is ready (UTC); the apps reload Top 10 then.
  final DateTime? nextUpdateAt;

  /// Throws [FormatException] when the lists are missing, so the caller falls
  /// back to the app's own rule.
  factory WeeklyTop10Dto.fromJson(Map<String, dynamic> json) {
    List<CatalogStreamDto> rows(Object? v, String name) {
      if (v is! List) throw FormatException('top10: $name is not a list');
      return [
        for (final e in v)
          if (e is Map) CatalogStreamDto.fromJson(Map<String, dynamic>.from(e)),
      ];
    }

    final next = json['nextUpdateAt'];
    return WeeklyTop10Dto(
      movies: rows(json['movies'], 'movies'),
      series: rows(json['series'], 'series'),
      week: json['week']?.toString(),
      nextUpdateAt: next is String ? DateTime.tryParse(next)?.toUtc() : null,
    );
  }
}
