import '../utils/display_name.dart';

enum MediaKind { movie, series, live, sports }

class MediaItem {
  const MediaItem({
    required this.id,
    required this.title,
    this.subtitle,
    this.titleArabic,
    required this.kind,
    this.year,
    this.rating,
    this.matchPercent,
    this.durationLabel,
    this.genres = const [],
    this.badges = const [],
    this.isOriginal = false,
    this.isLive = false,
    this.progress,
    this.progressLabel,
    this.synopsis,
    this.posterSeed,
    this.posterUrl,
    this.backdropUrl,
    this.streamUrl,
    this.containerExtension,
    this.categoryId,
    this.seriesId,
    this.resumePositionSec,
    this.addedSec,
  });

  final String id;
  final String title;
  final String? subtitle;
  final String? titleArabic;
  final MediaKind kind;

  /// Same row with another title (a saved channel renamed to its current
  /// catalog name).
  MediaItem withTitle(String title) => MediaItem(
        title: title,
        id: id,
        subtitle: subtitle,
        titleArabic: titleArabic,
        kind: kind,
        year: year,
        rating: rating,
        matchPercent: matchPercent,
        durationLabel: durationLabel,
        genres: genres,
        badges: badges,
        isOriginal: isOriginal,
        isLive: isLive,
        progress: progress,
        progressLabel: progressLabel,
        synopsis: synopsis,
        posterSeed: posterSeed,
        posterUrl: posterUrl,
        backdropUrl: backdropUrl,
        streamUrl: streamUrl,
        containerExtension: containerExtension,
        categoryId: categoryId,
        seriesId: seriesId,
        resumePositionSec: resumePositionSec,
        addedSec: addedSec,
      );

  /// Customer-facing title (symbols / language codes stripped).
  /// Never surfaces the catalog placeholder literal "Title".
  String get displayTitle {
    final cleaned =
        cleanDisplayName(title, keepQuality: kind == MediaKind.live).trim();
    if (cleaned.isNotEmpty && cleaned.toLowerCase() != 'title') {
      return cleaned;
    }
    return id.isNotEmpty ? id : 'Untitled';
  }
  final int? year;
  final double? rating;

  /// Rating shown on the poster: movies and series only, 0-10 (channels
  /// have none). Client 23 Oct round 3 #11: on every poster, as on TV.
  double? get posterRating {
    final r = rating;
    if (kind != MediaKind.movie && kind != MediaKind.series) return null;
    if (r == null || !r.isFinite || r <= 0 || r > 10) return null;
    return r;
  }
  final int? matchPercent;
  final String? durationLabel;
  final List<String> genres;
  final List<String> badges;
  final bool isOriginal;
  final bool isLive;
  final double? progress;
  final String? progressLabel;
  final String? synopsis;
  final int? posterSeed;
  /// Portrait artwork (Lorem Picsum / CDN sample).
  final String? posterUrl;
  /// Landscape hero / continue-watching art.
  final String? backdropUrl;
  /// Sample stream URL for Phase 1 player demos / lease playUrl.
  final String? streamUrl;
  /// VOD/series container from catalog (pass to playback/start).
  final String? containerExtension;
  final String? categoryId;
  /// Parent series when [id] is an episode stream id.
  final String? seriesId;
  /// Absolute resume offset from continue-watching (`positionSec`).
  final int? resumePositionSec;
  /// When the provider added the title (Unix seconds), if known. Used by the
  /// weekly Top 10 and banner (titles added this week wait until Friday).
  final int? addedSec;

  /// Same item with its wide scene image (episode still / movie backdrop).
  MediaItem withScene(String scene) => MediaItem(
    id: id,
    title: title,
    subtitle: subtitle,
    titleArabic: titleArabic,
    kind: kind,
    year: year,
    rating: rating,
    matchPercent: matchPercent,
    durationLabel: durationLabel,
    genres: genres,
    badges: badges,
    isOriginal: isOriginal,
    isLive: isLive,
    progress: progress,
    progressLabel: progressLabel,
    synopsis: synopsis,
    posterSeed: posterSeed,
    posterUrl: posterUrl,
    backdropUrl: scene,
    streamUrl: streamUrl,
    containerExtension: containerExtension,
    categoryId: categoryId,
    seriesId: seriesId,
    resumePositionSec: resumePositionSec,
    addedSec: addedSec,
  );

  /// Same item with catalog art filled in (Continue Watching rows saved
  /// without a poster showed blank cards, client 18 Oct).
  MediaItem withArt(String art) => MediaItem(
    id: id,
    title: title,
    subtitle: subtitle,
    titleArabic: titleArabic,
    kind: kind,
    year: year,
    rating: rating,
    matchPercent: matchPercent,
    durationLabel: durationLabel,
    genres: genres,
    badges: badges,
    isOriginal: isOriginal,
    isLive: isLive,
    progress: progress,
    progressLabel: progressLabel,
    synopsis: synopsis,
    posterSeed: posterSeed,
    posterUrl: art,
    backdropUrl: backdropUrl ?? art,
    streamUrl: streamUrl,
    containerExtension: containerExtension,
    categoryId: categoryId,
    seriesId: seriesId,
    resumePositionSec: resumePositionSec,
    addedSec: addedSec,
  );

  /// Player route. Series episodes keep the parent series id in the query.
  /// Includes [startSec] when a resume position is known, and [title] so the
  /// player chrome can show the stream name before catalog lookup finishes.
  String playbackRoute() {
    final start = resumePositionSec;
    final startQ =
        (start != null && start > 5) ? 'startSec=$start' : null;
    final title = displayTitle.trim();
    final titleQ = title.isNotEmpty
        ? 'title=${Uri.encodeQueryComponent(title)}'
        : null;
    if (kind == MediaKind.series) {
      final parent = seriesId;
      final parts = <String>['kind=series'];
      if (parent != null && parent.isNotEmpty && parent != id) {
        parts.add('seriesId=$parent');
      }
      if (startQ != null) parts.add(startQ);
      if (titleQ != null) parts.add(titleQ);
      return '/player/$id?${parts.join('&')}';
    }
    final parts = <String>['kind=${kind.name}'];
    if (startQ != null) parts.add(startQ);
    if (titleQ != null) parts.add(titleQ);
    return '/player/$id?${parts.join('&')}';
  }
}

/// Ids of the sample catalog used by early test builds ("movie-crimson",
/// "series-…"). Provider ids are numeric, so these never match a real
/// title; they were saved into some customers' My List (client 20 Oct).
bool isMockLibraryId(String id) =>
    RegExp(r'^(movie|series|vod|episode)[-_][a-z]', caseSensitive: false).hasMatch(id.trim());
