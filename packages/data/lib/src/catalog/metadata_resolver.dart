import 'dart:convert';

import 'package:domain/domain.dart';

import '../backend/catalog_models.dart';
import '../backend/json_util.dart';
import '../diag/diag.dart';
import '../providers/provider_models.dart';
import 'catalog_store.dart';

/// Calls the `metadata-tmdb` Edge Function with a JSON body.
typedef MetadataFetch = Future<Object?> Function(Map<String, dynamic> body);

/// Phase 6.3 — posters, plots, backdrops, ratings for the titles a user
/// actually sees or opens (never bulk). Asks the global catalog through
/// `metadata-tmdb` (TMDB key stays on the server), at most 25 titles per
/// call, tmdb id first, and keeps every answer in the local database so each
/// title is looked up once. "No match" is cached too and retried after
/// [missRetry] (admin `metadata.miss_retry_days`). The global catalog already
/// carries admin edits (`locked_fields`), so admin overrides win.
class MetadataResolver {
  MetadataResolver({
    required this.store,
    required MetadataFetch fetch,
    this.missRetry = const Duration(days: 7),
    DateTime Function()? clock,
  })  : _fetch = fetch,
        _clock = clock ?? DateTime.now;

  final CatalogStore store;
  final MetadataFetch _fetch;
  final Duration missRetry;
  final DateTime Function() _clock;
  final _inFlight = <String>{};

  static String keyOf(MetadataQuery q) {
    final kind = q.kind == CatalogKind.series ? 'series' : 'movie';
    if (q.tmdbId != null) return '$kind:tmdb:${q.tmdbId}';
    final t = (q.title ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    return '$kind:title:$t|${q.year ?? ''}';
  }

  /// From the local cache only (instant; no network).
  Future<Map<String, TitleMetadata?>> cached(List<MetadataQuery> queries) async {
    final rows = await store.metadata(queries.map(keyOf));
    return {for (final e in rows.entries) e.key: _parse(e.value.json)};
  }

  /// Cache first; asks the server for what's missing (or a stale "no
  /// match"). Network problems never throw — you get what is known.
  Future<Map<String, TitleMetadata?>> resolve(List<MetadataQuery> queries) async {
    final unique = {for (final q in queries) keyOf(q): q};
    final rows = await store.metadata(unique.keys);
    final now = _clock();
    final out = <String, TitleMetadata?>{};
    final missing = <MetadataQuery>[];
    for (final e in unique.entries) {
      final row = rows[e.key];
      final staleMiss = row != null && row.json == null && now.difference(row.fetchedAt) > missRetry;
      if (row != null && !staleMiss) {
        out[e.key] = _parse(row.json);
      } else if (!_inFlight.contains(e.key)) {
        missing.add(e.value);
      }
    }
    for (var i = 0; i < missing.length; i += MetadataQuery.maxBatch) {
      final part = missing.sublist(i, i + MetadataQuery.maxBatch > missing.length ? missing.length : i + MetadataQuery.maxBatch);
      final keys = part.map(keyOf).toList();
      _inFlight.addAll(keys);
      final sw = Stopwatch()..start();
      try {
        final reply = await _fetch({'action': 'resolve', 'items': [for (final q in part) q.toJson()]});
        final results = jsonMap(reply)['results'];
        final list = results is List ? results : const [];
        final save = <String, String?>{};
        var found = 0;
        for (var k = 0; k < keys.length; k++) {
          final raw = k < list.length ? list[k] : null;
          final meta = TitleMetadata.tryParse(raw);
          if (meta != null) found++;
          out[keys[k]] = meta;
          save[keys[k]] = meta == null ? null : jsonEncode(raw);
        }
        await store.saveMetadata(save, at: _clock());
        Diag.event('META', 'resolved ${part.length} titles in ${sw.elapsedMilliseconds}ms: $found matched, '
            '${part.length - found} no match (${part.where((q) => q.tmdbId != null).length} by tmdb id)');
      } catch (e) {
        Diag.event('META', 'resolve failed for ${part.length} titles: ${e.runtimeType}: $e — will retry later');
      } finally {
        _inFlight.removeAll(keys);
      }
    }
    return out;
  }

  static TitleMetadata? _parse(String? json) {
    if (json == null) return null;
    try {
      return TitleMetadata.tryParse(jsonDecode(json));
    } catch (_) {
      return null;
    }
  }
}

/// The query for a panel title: tmdb id when the panel gives one, else the
/// panel's raw name + year (the server cleans "AR: …", "(2023)", "4K" …).
MetadataQuery movieMetadataQuery(ProviderMovie m) => MetadataQuery(
      kind: CatalogKind.movie,
      tmdbId: m.tmdbId,
      title: m.tmdbId == null ? m.name : null,
      year: m.year,
    );

MetadataQuery seriesMetadataQuery(ProviderSeries s) => MetadataQuery(
      kind: CatalogKind.series,
      tmdbId: s.tmdbId,
      title: s.tmdbId == null ? s.name : null,
      year: s.year,
    );

/// Global-catalog values (incl. admin edits) win for plot, artwork and
/// rating; the panel's own title and ids stay as the user's panel shows them.
MediaItem enrichMedia(MediaItem m, TitleMetadata? meta, ArtworkUrls art) {
  if (meta == null) return m;
  return MediaItem(
    id: m.id,
    title: m.title,
    subtitle: m.subtitle,
    titleArabic: m.titleArabic,
    kind: m.kind,
    year: m.year ?? meta.year,
    rating: meta.rating ?? m.rating,
    matchPercent: m.matchPercent,
    durationLabel: m.durationLabel,
    genres: m.genres,
    badges: m.badges,
    isOriginal: m.isOriginal,
    isLive: m.isLive,
    progress: m.progress,
    progressLabel: m.progressLabel,
    synopsis: (meta.overview ?? '').trim().isNotEmpty ? meta.overview : m.synopsis,
    posterSeed: m.posterSeed,
    posterUrl: art.poster(meta.posterPath) ?? m.posterUrl,
    backdropUrl: art.backdrop(meta.backdropPath) ?? m.backdropUrl,
    streamUrl: m.streamUrl,
    containerExtension: m.containerExtension,
    categoryId: m.categoryId,
    seriesId: m.seriesId,
    resumePositionSec: m.resumePositionSec,
    addedSec: m.addedSec,
  );
}
