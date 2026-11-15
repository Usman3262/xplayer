import 'package:drift/drift.dart';

part 'catalog_db.g.dart';

/// Local copy of each panel's catalog (Phase 6). Built for big panels
/// (measured: 57k live / 187k movies / 50k series): everything is keyed by
/// panel, filled category by category, and read page by page through the
/// indexes below — never loaded whole into memory.
///
/// Holds no credentials and no stream URLs: only panel ids + the play
/// command (Stalker `cmd` / M3U URL) the adapter needs at play time.

@DataClassName('CategoryRow')
@TableIndex(name: 'categories_by_kind', columns: {#panelId, #kind, #sort})
class Categories extends Table {
  TextColumn get panelId => text()();

  /// live | movie | series
  TextColumn get kind => text()();
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get parentId => text().nullable()();

  /// Panel order.
  IntColumn get sort => integer()();

  /// 18+ (panel flag or name keyword): hidden unless unlocked with the PIN.
  BoolColumn get adult => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {panelId, kind, id};
}

@DataClassName('ChannelRow')
@TableIndex(name: 'channels_by_category', columns: {#panelId, #categoryId, #sort})
class Channels extends Table {
  TextColumn get panelId => text()();
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get number => integer().nullable()();
  TextColumn get logoUrl => text().nullable()();
  TextColumn get categoryId => text().nullable()();
  TextColumn get epgId => text().nullable()();
  IntColumn get catchupDays => integer().withDefault(const Constant(0))();
  IntColumn get addedSec => integer().nullable()();
  TextColumn get command => text().nullable()();

  /// Order inside its category as the panel sent it.
  IntColumn get sort => integer()();

  BoolColumn get adult => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {panelId, id};
}

@DataClassName('MovieRow')
@TableIndex(name: 'movies_by_category', columns: {#panelId, #categoryId, #sort})
@TableIndex(name: 'movies_by_added', columns: {#panelId, #addedSec})
@TableIndex(name: 'movies_by_tmdb', columns: {#tmdbId})
@TableIndex(name: 'movies_by_rating', columns: {#panelId, #rating})
class Movies extends Table {
  TextColumn get panelId => text()();
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get posterUrl => text().nullable()();
  RealColumn get rating => real().nullable()();
  IntColumn get year => integer().nullable()();
  TextColumn get categoryId => text().nullable()();
  IntColumn get addedSec => integer().nullable()();
  IntColumn get tmdbId => integer().nullable()();
  TextColumn get extension => text().nullable()();
  TextColumn get command => text().nullable()();
  IntColumn get sort => integer()();

  BoolColumn get adult => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {panelId, id};
}

@DataClassName('SeriesRow')
@TableIndex(name: 'series_by_category', columns: {#panelId, #categoryId, #sort})
@TableIndex(name: 'series_by_added', columns: {#panelId, #addedSec})
@TableIndex(name: 'series_by_tmdb', columns: {#tmdbId})
@TableIndex(name: 'series_by_rating', columns: {#panelId, #rating})
class SeriesItems extends Table {
  @override
  String get tableName => 'series';

  TextColumn get panelId => text()();
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get posterUrl => text().nullable()();
  TextColumn get backdropUrl => text().nullable()();
  TextColumn get plot => text().nullable()();

  /// Comma-separated.
  TextColumn get genres => text().withDefault(const Constant(''))();
  RealColumn get rating => real().nullable()();
  IntColumn get year => integer().nullable()();
  TextColumn get categoryId => text().nullable()();
  IntColumn get addedSec => integer().nullable()();
  IntColumn get tmdbId => integer().nullable()();
  IntColumn get sort => integer()();

  BoolColumn get adult => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {panelId, id};
}

@DataClassName('EpisodeRow')
@TableIndex(name: 'episodes_by_series', columns: {#panelId, #seriesId, #season, #number})
class Episodes extends Table {
  TextColumn get panelId => text()();
  TextColumn get seriesId => text()();
  TextColumn get id => text()();
  IntColumn get season => integer()();
  IntColumn get number => integer()();
  TextColumn get title => text()();
  IntColumn get durationSec => integer().nullable()();
  TextColumn get plot => text().nullable()();
  TextColumn get stillUrl => text().nullable()();
  TextColumn get extension => text().nullable()();
  TextColumn get command => text().nullable()();

  @override
  Set<Column> get primaryKey => {panelId, id};
}

/// Programme guide window (kept for `cache.epg_retention_hours`).
@DataClassName('EpgRow')
@TableIndex(name: 'epg_by_end', columns: {#panelId, #endSec})
class Epg extends Table {
  TextColumn get panelId => text()();
  TextColumn get channelId => text()();
  IntColumn get startSec => integer()();
  IntColumn get endSec => integer()();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();

  @override
  Set<Column> get primaryKey => {panelId, channelId, startSec};
}

/// What was synced when (per panel + scope, e.g. "movie:cat:156",
/// "live:categories", "series:13801:episodes").
@DataClassName('SyncRow')
class SyncState extends Table {
  TextColumn get panelId => text()();
  TextColumn get scope => text()();
  IntColumn get syncedAtSec => integer()();
  IntColumn get itemCount => integer().withDefault(const Constant(0))();

  /// Newest `added` seen (cheap "what's new" check next time).
  IntColumn get maxAddedSec => integer().nullable()();

  @override
  Set<Column> get primaryKey => {panelId, scope};
}

/// Global-catalog metadata (via `metadata-tmdb`), fetched once per title and
/// shared by all panels. [json] null = "no confident match" (retried later).
@DataClassName('MetadataRow')
class MetadataCache extends Table {
  /// "movie:tmdb:123" or "series:title:the office|2005".
  TextColumn get key => text()();
  TextColumn get json => text().nullable()();
  IntColumn get fetchedAtSec => integer()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [Categories, Channels, Movies, SeriesItems, Episodes, Epg, SyncState, MetadataCache])
class CatalogDb extends _$CatalogDb {
  CatalogDb(super.e);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(metadataCache);
            await m.createIndex(Index('movies_by_rating',
                'CREATE INDEX IF NOT EXISTS movies_by_rating ON movies (panel_id, rating)'));
            await m.createIndex(Index('series_by_rating',
                'CREATE INDEX IF NOT EXISTS series_by_rating ON series (panel_id, rating)'));
          }
          if (from < 3) {
            // Adult (18+) flags; filled from the next category sync (category
            // flags also mark their existing items, no full re-sync needed).
            await m.addColumn(categories, categories.adult);
            await m.addColumn(channels, channels.adult);
            await m.addColumn(movies, movies.adult);
            await m.addColumn(seriesItems, seriesItems.adult);
          }
        },
        beforeOpen: (details) async {
          // WAL: readers (screens) don't wait for the sync writer.
          await customStatement('PRAGMA journal_mode = WAL');
          await customStatement('PRAGMA synchronous = NORMAL');
        },
      );
}
