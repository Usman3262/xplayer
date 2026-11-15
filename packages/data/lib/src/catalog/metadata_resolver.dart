import 'dart:async';
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

  /// Cache first; what's missing goes into ONE shared queue for the whole
  /// app: at most [maxInFlight] calls at a time, ≤25 titles each, every
  /// title asked once even if many screens want it. Network problems never
  /// throw — you get what is known.
  Future<Map<String, TitleMetadata?>> resolve(List<MetadataQuery> queries) async {
    final unique = {for (final q in queries) keyOf(q): q};
    final rows = await store.metadata(unique.keys);
    final now = _clock();
    final out = <String, TitleMetadata?>{};
    final waits = <String, Future<TitleMetadata?>>{};
    for (final e in unique.entries) {
      final row = rows[e.key];
      final staleMiss = row != null && row.json == null && now.difference(row.fetchedAt) > missRetry;
      if (row != null && !staleMiss) {
        out[e.key] = _parse(row.json);
        continue;
      }
      final pending = _pending[e.key];
      if (pending != null) {
        waits[e.key] = pending.future;
      } else {
        final c = Completer<TitleMetadata?>();
        _pending[e.key] = c;
        _queue.add(e.value);
        waits[e.key] = c.future;
      }
    }
    _pump();
    for (final w in waits.entries) {
      out[w.key] = await w.value;
    }
    return out;
  }

  /// Calls running at once (the server fetches each new title from TMDB).
  static const maxInFlight = 2;
  final _queue = <MetadataQuery>[];
  final _pending = <String, Completer<TitleMetadata?>>{};
  int _running = 0;

  void _pump() {
    while (_running < maxInFlight && _queue.isNotEmpty) {
      final n = _queue.length < MetadataQuery.maxBatch ? _queue.length : MetadataQuery.maxBatch;
      final part = _queue.sublist(0, n);
      _queue.removeRange(0, n);
      _running++;
      _fetchBatch(part).whenComplete(() {
        _running--;
        _pump();
      });
    }
  }

  Future<void> _fetchBatch(List<MetadataQuery> part) async {
    final keys = part.map(keyOf).toList();
    final sw = Stopwatch()..start();
    final results = <String, TitleMetadata?>{};
    try {
      final reply = await _fetch({'action': 'resolve', 'items': [for (final q in part) q.toJson()]});
      final raw = jsonMap(reply)['results'];
      final list = raw is List ? raw : const [];
      final save = <String, String?>{};
      var found = 0;
      for (var k = 0; k < keys.length; k++) {
        final item = k < list.length ? list[k] : null;
        final meta = TitleMetadata.tryParse(item);
        if (meta != null) found++;
        results[keys[k]] = meta;
        save[keys[k]] = meta == null ? null : jsonEncode(item);
      }
      await store.saveMetadata(save, at: _clock());
      Diag.event('META', 'resolved ${part.length} titles in ${sw.elapsedMilliseconds}ms: $found matched, '
          '${part.length - found} no match (${part.where((q) => q.tmdbId != null).length} by tmdb id), '
          '${_queue.length} waiting');
    } catch (e) {
      Diag.event('META', 'resolve failed for ${part.length} titles after ${sw.elapsedMilliseconds}ms: '
          '${e.runtimeType}: $e — will retry later');
    } finally {
      for (final k in keys) {
        _pending.remove(k)?.complete(results[k]);
      }
    }
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
