import 'package:domain/domain.dart';
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../backend/catalog_models.dart' show CatalogKind;
import '../providers/provider_models.dart';
import 'catalog_db.dart';

class CatalogCounts {
  const CatalogCounts({this.live = 0, this.movies = 0, this.series = 0, this.episodes = 0});
  final int live;
  final int movies;
  final int series;
  final int episodes;
}

class SyncInfo {
  const SyncInfo({required this.syncedAt, required this.itemCount, this.maxAddedSec});
  final DateTime syncedAt;
  final int itemCount;
  final int? maxAddedSec;
}

/// Read/write API over [CatalogDb]. Writes replace one category (or one
/// series' episodes) at a time in a single transaction, so a half-finished
/// sync never leaves a category half old / half new. Reads are paged.
class CatalogStore {
  CatalogStore(this.db);

  /// On-device database (queries run on a background isolate).
  factory CatalogStore.open({String name = 'xplayer_catalog'}) => CatalogStore(CatalogDb(driftDatabase(name: name)));

  final CatalogDb db;

  static const _chunk = 1000;

  Future<void> close() => db.close();

  // ── Categories ───────────────────────────────────────────────────────────

  /// Replaces the panel's category list for [kind] (order kept). [isAdult]
  /// decides 18+ (default: the panel's flag); adult categories also mark
  /// the items already stored in them.
  Future<void> saveCategories(String panelId, CatalogKind kind, List<ProviderCategory> list,
          {bool Function(ProviderCategory c)? isAdult}) =>
      db.transaction(() async {
        bool adultOf(ProviderCategory c) => isAdult?.call(c) ?? c.adult;
        await (db.delete(db.categories)..where((c) => c.panelId.equals(panelId) & c.kind.equals(kind.name))).go();
        await _insertChunks(db.categories, [
          for (var i = 0; i < list.length; i++)
            CategoriesCompanion.insert(
              panelId: panelId,
              kind: kind.name,
              id: list[i].id,
              name: list[i].name,
              parentId: Value(list[i].parentId),
              sort: i,
              adult: Value(adultOf(list[i])),
            ),
        ]);
        final adultIds = [for (final c in list) if (adultOf(c)) c.id];
        if (adultIds.isEmpty) return;
        switch (kind) {
          case CatalogKind.live:
            await (db.update(db.channels)..where((t) => t.panelId.equals(panelId) & t.categoryId.isIn(adultIds)))
                .write(const ChannelsCompanion(adult: Value(true)));
          case CatalogKind.movie:
            await (db.update(db.movies)..where((t) => t.panelId.equals(panelId) & t.categoryId.isIn(adultIds)))
                .write(const MoviesCompanion(adult: Value(true)));
          case CatalogKind.series:
            await (db.update(db.seriesItems)..where((t) => t.panelId.equals(panelId) & t.categoryId.isIn(adultIds)))
                .write(const SeriesItemsCompanion(adult: Value(true)));
        }
      });

  /// Is this category 18+ (as saved by the last category sync)?
  Future<bool> _categoryAdult(String panelId, CatalogKind kind, String? categoryId) async {
    if (categoryId == null) return false;
    final r = await (db.select(db.categories)
          ..where((c) => c.panelId.equals(panelId) & c.kind.equals(kind.name) & c.id.equals(categoryId)))
        .getSingleOrNull();
    return r?.adult ?? false;
  }

  /// [adult]: false = normal (18+ hidden), true = only 18+, null = all.
  Future<List<ProviderCategory>> categories(String panelId, CatalogKind kind, {bool? adult = false}) async {
    final q = db.select(db.categories)
      ..where((c) => c.panelId.equals(panelId) & c.kind.equals(kind.name))
      ..orderBy([(c) => OrderingTerm(expression: c.sort)]);
    if (adult != null) q.where((c) => c.adult.equals(adult));
    return [for (final r in await q.get()) ProviderCategory(id: r.id, name: r.name, parentId: r.parentId, adult: r.adult)];
  }

  /// Deletes items whose category the panel no longer has ([keepIds] =
  /// the current category ids for [kind]). Items without a category stay.
  Future<int> pruneMissingCategories(String panelId, CatalogKind kind, Set<String> keepIds) =>
      db.transaction(() async {
        final keep = keepIds.toList();
        switch (kind) {
          case CatalogKind.live:
            return (db.delete(db.channels)
                  ..where((t) => t.panelId.equals(panelId) & t.categoryId.isNotNull() & t.categoryId.isNotIn(keep)))
                .go();
          case CatalogKind.movie:
            return (db.delete(db.movies)
                  ..where((t) => t.panelId.equals(panelId) & t.categoryId.isNotNull() & t.categoryId.isNotIn(keep)))
                .go();
          case CatalogKind.series:
            return (db.delete(db.seriesItems)
                  ..where((t) => t.panelId.equals(panelId) & t.categoryId.isNotNull() & t.categoryId.isNotIn(keep)))
                .go();
        }
      });

  // ── Live ─────────────────────────────────────────────────────────────────

  /// Replaces one category's channels ([categoryId] null = the whole list).
  Future<void> saveChannels(String panelId, String? categoryId, List<ProviderChannel> list) =>
      db.transaction(() async {
        final catAdult = await _categoryAdult(panelId, CatalogKind.live, categoryId);
        final del = db.delete(db.channels)..where((c) => c.panelId.equals(panelId));
        if (categoryId != null) del.where((c) => c.categoryId.equals(categoryId));
        await del.go();
        await _insertChunks(db.channels, [
          for (var i = 0; i < list.length; i++)
            ChannelsCompanion.insert(
              panelId: panelId,
              id: list[i].id,
              name: list[i].name,
              number: Value(list[i].number),
              logoUrl: Value(list[i].logoUrl),
              categoryId: Value(list[i].categoryId ?? categoryId),
              epgId: Value(list[i].epgId),
              catchupDays: Value(list[i].catchupDays),
              addedSec: Value(list[i].addedSec),
              command: Value(list[i].stream.command),
              sort: i,
              adult: Value(catAdult || list[i].adult),
            ),
        ]);
      });

  /// A page of channels in panel order; pass the last row's `sort` as
  /// [afterSort] for the next page.
  Future<List<(ProviderChannel, int)>> channels(String panelId, {String? categoryId, int limit = 60, int? afterSort, bool? adult = false}) async {
    final q = db.select(db.channels)..where((c) => c.panelId.equals(panelId));
    if (adult != null) q.where((c) => c.adult.equals(adult));
    if (categoryId != null) q.where((c) => c.categoryId.equals(categoryId));
    if (afterSort != null) q.where((c) => c.sort.isBiggerThanValue(afterSort));
    q
      ..orderBy([(c) => OrderingTerm(expression: c.sort), (c) => OrderingTerm(expression: c.id)])
      ..limit(limit);
    return [for (final r in await q.get()) (_channel(r), r.sort)];
  }

  Future<ProviderChannel?> channel(String panelId, String id) async {
    final r = await (db.select(db.channels)..where((c) => c.panelId.equals(panelId) & c.id.equals(id))).getSingleOrNull();
    return r == null ? null : _channel(r);
  }

  static ProviderChannel _channel(ChannelRow r) => ProviderChannel(
        id: r.id,
        name: r.name,
        stream: StreamRef(kind: MediaKind.live, id: r.id, command: r.command),
        number: r.number,
        logoUrl: r.logoUrl,
        categoryId: r.categoryId,
        epgId: r.epgId,
        catchupDays: r.catchupDays,
        addedSec: r.addedSec,
        adult: r.adult,
      );

  // ── Movies ───────────────────────────────────────────────────────────────

  Future<void> saveMovies(String panelId, String? categoryId, List<ProviderMovie> list) => db.transaction(() async {
        final catAdult = await _categoryAdult(panelId, CatalogKind.movie, categoryId);
        final del = db.delete(db.movies)..where((m) => m.panelId.equals(panelId));
        if (categoryId != null) del.where((m) => m.categoryId.equals(categoryId));
        await del.go();
        await _insertChunks(db.movies, [
          for (var i = 0; i < list.length; i++)
            MoviesCompanion.insert(
              panelId: panelId,
              id: list[i].id,
              name: list[i].name,
              posterUrl: Value(list[i].posterUrl),
              rating: Value(list[i].rating),
              year: Value(list[i].year),
              categoryId: Value(list[i].categoryId ?? categoryId),
              addedSec: Value(list[i].addedSec),
              tmdbId: Value(list[i].tmdbId),
              extension: Value(list[i].stream.extension),
              command: Value(list[i].stream.command),
              sort: i,
              adult: Value(catAdult || list[i].adult),
            ),
        ]);
      });

  Future<List<(ProviderMovie, int)>> movies(String panelId, {String? categoryId, int limit = 60, int? afterSort, bool? adult = false}) async {
    final q = db.select(db.movies)..where((m) => m.panelId.equals(panelId));
    if (adult != null) q.where((m) => m.adult.equals(adult));
    if (categoryId != null) q.where((m) => m.categoryId.equals(categoryId));
    if (afterSort != null) q.where((m) => m.sort.isBiggerThanValue(afterSort));
    q
      ..orderBy([(m) => OrderingTerm(expression: m.sort), (m) => OrderingTerm(expression: m.id)])
      ..limit(limit);
    return [for (final r in await q.get()) (_movie(r), r.sort)];
  }

  /// Newest by the panel's `added` (the "Recently added" rails come from
  /// the panel, never TMDB). Keyset: pass the last movie for the next page.
  Future<List<ProviderMovie>> newestMovies(String panelId, {int limit = 20, ProviderMovie? after, bool? adult = false}) async {
    final q = db.select(db.movies)..where((m) => m.panelId.equals(panelId) & m.addedSec.isNotNull());
    if (adult != null) q.where((m) => m.adult.equals(adult));
    if (after?.addedSec != null) {
      final a = after!.addedSec!;
      q.where((m) => m.addedSec.isSmallerThanValue(a) | (m.addedSec.equals(a) & m.id.isSmallerThanValue(after.id)));
    }
    q
      ..orderBy([(m) => OrderingTerm.desc(m.addedSec), (m) => OrderingTerm.desc(m.id)])
      ..limit(limit);
    return [for (final r in await q.get()) _movie(r)];
  }

  Future<ProviderMovie?> movie(String panelId, String id) async {
    final r = await (db.select(db.movies)..where((m) => m.panelId.equals(panelId) & m.id.equals(id))).getSingleOrNull();
    return r == null ? null : _movie(r);
  }

  static ProviderMovie _movie(MovieRow r) => ProviderMovie(
        id: r.id,
        name: r.name,
        stream: StreamRef(kind: MediaKind.movie, id: r.id, extension: r.extension, command: r.command),
        posterUrl: r.posterUrl,
        rating: r.rating,
        year: r.year,
        categoryId: r.categoryId,
        addedSec: r.addedSec,
        tmdbId: r.tmdbId,
        adult: r.adult,
      );

  // ── Series ───────────────────────────────────────────────────────────────

  Future<void> saveSeries(String panelId, String? categoryId, List<ProviderSeries> list) => db.transaction(() async {
        final catAdult = await _categoryAdult(panelId, CatalogKind.series, categoryId);
        final del = db.delete(db.seriesItems)..where((s) => s.panelId.equals(panelId));
        if (categoryId != null) del.where((s) => s.categoryId.equals(categoryId));
        await del.go();
        await _insertChunks(db.seriesItems, [
          for (var i = 0; i < list.length; i++) _seriesCompanion(panelId, list[i], categoryId, i, adult: catAdult || list[i].adult),
        ]);
      });

  static SeriesItemsCompanion _seriesCompanion(String panelId, ProviderSeries s, String? categoryId, int sort, {bool adult = false}) =>
      SeriesItemsCompanion.insert(
        panelId: panelId,
        id: s.id,
        name: s.name,
        posterUrl: Value(s.posterUrl),
        backdropUrl: Value(s.backdropUrl),
        plot: Value(s.plot),
        genres: Value(s.genres.join(',')),
        rating: Value(s.rating),
        year: Value(s.year),
        categoryId: Value(s.categoryId ?? categoryId),
        addedSec: Value(s.addedSec),
        tmdbId: Value(s.tmdbId),
        sort: sort,
        adult: Value(adult),
      );

  Future<List<(ProviderSeries, int)>> series(String panelId, {String? categoryId, int limit = 60, int? afterSort, bool? adult = false}) async {
    final q = db.select(db.seriesItems)..where((s) => s.panelId.equals(panelId));
    if (adult != null) q.where((s) => s.adult.equals(adult));
    if (categoryId != null) q.where((s) => s.categoryId.equals(categoryId));
    if (afterSort != null) q.where((s) => s.sort.isBiggerThanValue(afterSort));
    q
      ..orderBy([(s) => OrderingTerm(expression: s.sort), (s) => OrderingTerm(expression: s.id)])
      ..limit(limit);
    return [for (final r in await q.get()) (_series(r), r.sort)];
  }

  Future<List<ProviderSeries>> newestSeries(String panelId, {int limit = 20, ProviderSeries? after, bool? adult = false}) async {
    final q = db.select(db.seriesItems)..where((s) => s.panelId.equals(panelId) & s.addedSec.isNotNull());
    if (adult != null) q.where((s) => s.adult.equals(adult));
    if (after?.addedSec != null) {
      final a = after!.addedSec!;
      q.where((s) => s.addedSec.isSmallerThanValue(a) | (s.addedSec.equals(a) & s.id.isSmallerThanValue(after.id)));
    }
    q
      ..orderBy([(s) => OrderingTerm.desc(s.addedSec), (s) => OrderingTerm.desc(s.id)])
      ..limit(limit);
    return [for (final r in await q.get()) _series(r)];
  }

  static ProviderSeries _series(SeriesRow r) => ProviderSeries(
        id: r.id,
        name: r.name,
        posterUrl: r.posterUrl,
        backdropUrl: r.backdropUrl,
        plot: r.plot,
        genres: r.genres.isEmpty ? const [] : r.genres.split(','),
        rating: r.rating,
        year: r.year,
        categoryId: r.categoryId,
        addedSec: r.addedSec,
        tmdbId: r.tmdbId,
        adult: r.adult,
      );

  /// Saves a series' seasons/episodes (fetched when the user opens it) and
  /// refreshes the series row with the details' info.
  Future<void> saveSeriesDetails(String panelId, ProviderSeriesDetails d) => db.transaction(() async {
        final seriesId = d.series.id;
        final existing = await (db.select(db.seriesItems)
              ..where((s) => s.panelId.equals(panelId) & s.id.equals(seriesId)))
            .getSingleOrNull();
        await db.into(db.seriesItems).insertOnConflictUpdate(
              _seriesCompanion(panelId, d.series, existing?.categoryId, existing?.sort ?? 1 << 30,
                  adult: (existing?.adult ?? false) || d.series.adult),
            );
        await (db.delete(db.episodes)..where((e) => e.panelId.equals(panelId) & e.seriesId.equals(seriesId))).go();
        await _insertChunks(db.episodes, [
          for (final list in d.episodes.values)
            for (final e in list)
              EpisodesCompanion.insert(
                panelId: panelId,
                seriesId: seriesId,
                id: e.id,
                season: e.season,
                number: e.number,
                title: e.title,
                durationSec: Value(e.durationSec),
                plot: Value(e.plot),
                stillUrl: Value(e.stillUrl),
                extension: Value(e.stream.extension),
                command: Value(e.stream.command),
              ),
        ]);
      });

  /// Cached details, or null if the series was never opened.
  Future<ProviderSeriesDetails?> seriesDetails(String panelId, String seriesId) async {
    final s = await (db.select(db.seriesItems)..where((x) => x.panelId.equals(panelId) & x.id.equals(seriesId)))
        .getSingleOrNull();
    if (s == null) return null;
    final rows = await (db.select(db.episodes)
          ..where((e) => e.panelId.equals(panelId) & e.seriesId.equals(seriesId))
          ..orderBy([(e) => OrderingTerm(expression: e.season), (e) => OrderingTerm(expression: e.number)]))
        .get();
    if (rows.isEmpty) return null;
    final episodes = <int, List<ProviderEpisode>>{};
    for (final r in rows) {
      episodes.putIfAbsent(r.season, () => []).add(ProviderEpisode(
            id: r.id,
            seriesId: seriesId,
            season: r.season,
            number: r.number,
            title: r.title,
            stream: StreamRef(kind: MediaKind.series, id: r.id, extension: r.extension, command: r.command),
            durationSec: r.durationSec,
            plot: r.plot,
            stillUrl: r.stillUrl,
          ));
    }
    return ProviderSeriesDetails(series: _series(s), episodes: episodes);
  }

  // ── EPG ──────────────────────────────────────────────────────────────────

  Future<void> saveEpg(String panelId, String channelId, List<EpgEntry> entries) => db.transaction(() async {
        if (entries.isEmpty) return;
        await _insertChunks(db.epg, [
          for (final e in entries)
            EpgCompanion.insert(
              panelId: panelId,
              channelId: channelId,
              startSec: e.start.millisecondsSinceEpoch ~/ 1000,
              endSec: e.end.millisecondsSinceEpoch ~/ 1000,
              title: e.title,
              description: Value(e.description),
            ),
        ], replace: true);
      });

  /// Programmes for a channel that haven't ended at [from].
  Future<List<EpgEntry>> epg(String panelId, String channelId, {required DateTime from, int limit = 6}) async {
    final fromSec = from.millisecondsSinceEpoch ~/ 1000;
    final rows = await (db.select(db.epg)
          ..where((e) => e.panelId.equals(panelId) & e.channelId.equals(channelId) & e.endSec.isBiggerThanValue(fromSec))
          ..orderBy([(e) => OrderingTerm(expression: e.startSec)])
          ..limit(limit))
        .get();
    return [
      for (final r in rows)
        EpgEntry(
          title: r.title,
          description: r.description,
          start: DateTime.fromMillisecondsSinceEpoch(r.startSec * 1000, isUtc: true),
          end: DateTime.fromMillisecondsSinceEpoch(r.endSec * 1000, isUtc: true),
        ),
    ];
  }

  /// Drops guide entries that ended before [before] (retention job).
  Future<int> pruneEpg(String panelId, DateTime before) => (db.delete(db.epg)
        ..where((e) => e.panelId.equals(panelId) & e.endSec.isSmallerThanValue(before.millisecondsSinceEpoch ~/ 1000)))
      .go();

  // ── Sync bookkeeping ─────────────────────────────────────────────────────

  Future<void> markSynced(String panelId, String scope, {required DateTime at, int count = 0, int? maxAddedSec}) =>
      db.into(db.syncState).insertOnConflictUpdate(SyncStateCompanion.insert(
            panelId: panelId,
            scope: scope,
            syncedAtSec: at.millisecondsSinceEpoch ~/ 1000,
            itemCount: Value(count),
            maxAddedSec: Value(maxAddedSec),
          ));

  Future<void> clearSync(String panelId, String scope) =>
      (db.delete(db.syncState)..where((t) => t.panelId.equals(panelId) & t.scope.equals(scope))).go();

  Future<SyncInfo?> syncInfo(String panelId, String scope) async {
    final r = await (db.select(db.syncState)..where((s) => s.panelId.equals(panelId) & s.scope.equals(scope)))
        .getSingleOrNull();
    return r == null
        ? null
        : SyncInfo(
            syncedAt: DateTime.fromMillisecondsSinceEpoch(r.syncedAtSec * 1000, isUtc: true),
            itemCount: r.itemCount,
            maxAddedSec: r.maxAddedSec,
          );
  }

  // ── Lookups for Home sections / search / details ─────────────────────────

  /// Best rated first (panel rating), keyset by offset (small pages only).
  Future<List<ProviderMovie>> topRatedMovies(String panelId, {int limit = 20, int offset = 0}) async {
    final rows = await (db.select(db.movies)
          ..where((m) => m.panelId.equals(panelId) & m.rating.isNotNull() & m.adult.equals(false))
          ..orderBy([(m) => OrderingTerm.desc(m.rating), (m) => OrderingTerm.desc(m.addedSec)])
          ..limit(limit, offset: offset))
        .get();
    return [for (final r in rows) _movie(r)];
  }

  Future<List<ProviderSeries>> topRatedSeries(String panelId, {int limit = 20, int offset = 0}) async {
    final rows = await (db.select(db.seriesItems)
          ..where((s) => s.panelId.equals(panelId) & s.rating.isNotNull() & s.adult.equals(false))
          ..orderBy([(s) => OrderingTerm.desc(s.rating), (s) => OrderingTerm.desc(s.addedSec)])
          ..limit(limit, offset: offset))
        .get();
    return [for (final r in rows) _series(r)];
  }

  Future<List<ProviderMovie>> moviesByIds(String panelId, Iterable<String> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return const [];
    final rows = await (db.select(db.movies)..where((m) => m.panelId.equals(panelId) & m.id.isIn(list))).get();
    final byId = {for (final r in rows) r.id: _movie(r)};
    return [for (final id in list) ?byId[id]];
  }

  Future<List<ProviderSeries>> seriesByIds(String panelId, Iterable<String> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return const [];
    final rows = await (db.select(db.seriesItems)..where((s) => s.panelId.equals(panelId) & s.id.isIn(list))).get();
    final byId = {for (final r in rows) r.id: _series(r)};
    return [for (final id in list) ?byId[id]];
  }

  Future<ProviderSeries?> seriesItem(String panelId, String id) async {
    final r = await (db.select(db.seriesItems)..where((s) => s.panelId.equals(panelId) & s.id.equals(id))).getSingleOrNull();
    return r == null ? null : _series(r);
  }

  Future<ProviderMovie?> movieByTmdb(String panelId, int tmdbId) async {
    final r = await (db.select(db.movies)
          ..where((m) => m.panelId.equals(panelId) & m.tmdbId.equals(tmdbId) & m.adult.equals(false))
          ..limit(1))
        .getSingleOrNull();
    return r == null ? null : _movie(r);
  }

  Future<ProviderSeries?> seriesByTmdb(String panelId, int tmdbId) async {
    final r = await (db.select(db.seriesItems)
          ..where((s) => s.panelId.equals(panelId) & s.tmdbId.equals(tmdbId) & s.adult.equals(false))
          ..limit(1))
        .getSingleOrNull();
    return r == null ? null : _series(r);
  }

  /// Name contains [q] (case-insensitive; `%`/`_` taken literally).
  /// Simple LIKE for now — full-text search is Phase 7.5.
  Future<List<ProviderMovie>> searchMovies(String panelId, String q, {int limit = 40, int offset = 0, String? categoryId, bool? adult = false}) async {
    final pattern = _like(q);
    if (pattern == null) return const [];
    final query = db.select(db.movies)
      ..where((m) => m.panelId.equals(panelId) & _nameLike(m.name, pattern));
    if (adult != null) query.where((m) => m.adult.equals(adult));
    if (categoryId != null) query.where((m) => m.categoryId.equals(categoryId));
    query
      ..orderBy([(m) => OrderingTerm.desc(m.addedSec)])
      ..limit(limit, offset: offset);
    return [for (final r in await query.get()) _movie(r)];
  }

  Future<List<ProviderSeries>> searchSeries(String panelId, String q, {int limit = 40, int offset = 0, String? categoryId, bool? adult = false}) async {
    final pattern = _like(q);
    if (pattern == null) return const [];
    final query = db.select(db.seriesItems)
      ..where((s) => s.panelId.equals(panelId) & _nameLike(s.name, pattern));
    if (adult != null) query.where((s) => s.adult.equals(adult));
    if (categoryId != null) query.where((s) => s.categoryId.equals(categoryId));
    query
      ..orderBy([(s) => OrderingTerm.desc(s.addedSec)])
      ..limit(limit, offset: offset);
    return [for (final r in await query.get()) _series(r)];
  }

  Future<List<ProviderChannel>> searchChannels(String panelId, String q, {int limit = 40, int offset = 0, String? categoryId, bool? adult = false}) async {
    final pattern = _like(q);
    if (pattern == null) return const [];
    final query = db.select(db.channels)
      ..where((c) => c.panelId.equals(panelId) & _nameLike(c.name, pattern));
    if (adult != null) query.where((c) => c.adult.equals(adult));
    if (categoryId != null) query.where((c) => c.categoryId.equals(categoryId));
    query
      ..orderBy([(c) => OrderingTerm(expression: c.sort)])
      ..limit(limit, offset: offset);
    return [for (final r in await query.get()) _channel(r)];
  }

  /// First matching item by exact (case-insensitive) name — admin picks
  /// that only carry a title.
  Future<ProviderMovie?> movieByName(String panelId, String name) async =>
      (await searchMovies(panelId, name, limit: 20)).where((m) => m.name.toLowerCase() == name.trim().toLowerCase()).firstOrNull ??
      (await searchMovies(panelId, name, limit: 1)).firstOrNull;

  Future<ProviderSeries?> seriesByName(String panelId, String name) async =>
      (await searchSeries(panelId, name, limit: 20)).where((s) => s.name.toLowerCase() == name.trim().toLowerCase()).firstOrNull ??
      (await searchSeries(panelId, name, limit: 1)).firstOrNull;

  /// Search words → one LIKE pattern each (all must match, any order:
  /// "night dark" finds "The Dark Night"). At most 5 words. Plain LIKE was
  /// measured fast enough (130k titles: ≤45 ms on a PC, decision D20).
  static List<String>? _like(String q) {
    final words = q.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(5).toList();
    if (words.isEmpty) return null;
    return [
      for (final w in words) '%${w.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_')}%',
    ];
  }

  static Expression<bool> _nameLike(GeneratedColumn<String> name, List<String> patterns) =>
      patterns.map((p) => name.like(p, escapeChar: r'\')).reduce((a, b) => a & b);

  // ── Metadata cache (global catalog via metadata-tmdb) ────────────────────

  /// Cached entries for [keys]: found → json (may be null = "no match").
  Future<Map<String, ({String? json, DateTime fetchedAt})>> metadata(Iterable<String> keys) async {
    final list = keys.toList();
    if (list.isEmpty) return const {};
    final rows = await (db.select(db.metadataCache)..where((m) => m.key.isIn(list))).get();
    return {
      for (final r in rows)
        r.key: (json: r.json, fetchedAt: DateTime.fromMillisecondsSinceEpoch(r.fetchedAtSec * 1000, isUtc: true)),
    };
  }

  Future<void> saveMetadata(Map<String, String?> entries, {required DateTime at}) async {
    if (entries.isEmpty) return;
    await _insertChunks(db.metadataCache, [
      for (final e in entries.entries)
        MetadataCacheCompanion.insert(key: e.key, json: Value(e.value), fetchedAtSec: at.millisecondsSinceEpoch ~/ 1000),
    ], replace: true);
  }

  // ── Panel-wide ───────────────────────────────────────────────────────────

  Future<CatalogCounts> counts(String panelId) async {
    Future<int> count(TableInfo t, Expression<String> panelCol) async {
      final c = countAll();
      final row = await (db.selectOnly(t)
            ..addColumns([c])
            ..where(panelCol.equals(panelId)))
          .getSingle();
      return row.read(c) ?? 0;
    }

    return CatalogCounts(
      live: await count(db.channels, db.channels.panelId),
      movies: await count(db.movies, db.movies.panelId),
      series: await count(db.seriesItems, db.seriesItems.panelId),
      episodes: await count(db.episodes, db.episodes.panelId),
    );
  }

  /// Everything of a removed panel (Settings → remove / device sign-out).
  Future<void> clearPanel(String panelId) => db.transaction(() async {
        await (db.delete(db.categories)..where((t) => t.panelId.equals(panelId))).go();
        await (db.delete(db.channels)..where((t) => t.panelId.equals(panelId))).go();
        await (db.delete(db.movies)..where((t) => t.panelId.equals(panelId))).go();
        await (db.delete(db.seriesItems)..where((t) => t.panelId.equals(panelId))).go();
        await (db.delete(db.episodes)..where((t) => t.panelId.equals(panelId))).go();
        await (db.delete(db.epg)..where((t) => t.panelId.equals(panelId))).go();
        await (db.delete(db.syncState)..where((t) => t.panelId.equals(panelId))).go();
      });

  Future<void> _insertChunks<T extends Table, R>(TableInfo<T, R> table, List<Insertable<R>> rows, {bool replace = false}) async {
    for (var i = 0; i < rows.length; i += _chunk) {
      final part = rows.sublist(i, i + _chunk > rows.length ? rows.length : i + _chunk);
      await db.batch((b) => replace ? b.insertAllOnConflictUpdate(table, part) : b.insertAll(table, part, mode: InsertMode.insertOrReplace));
    }
  }
}
