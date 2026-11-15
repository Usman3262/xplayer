import 'dart:async';

import 'package:flutter/foundation.dart';

import '../backend/catalog_models.dart' show CatalogKind;
import '../backend/remote_config.dart';
import '../diag/diag.dart';
import '../providers/provider_adapter.dart';
import '../providers/provider_models.dart';
import 'catalog_store.dart';

/// How the sync behaves. Built-in defaults; admin config overrides
/// (App customization → Versions → Cache & refresh).
@immutable
class SyncPolicy {
  const SyncPolicy({
    this.ttl = const Duration(hours: 12),
    this.parallelCategories = 2,
    this.maxConsecutiveFailures = 5,
    this.epgRetention = const Duration(hours: 48),
  });

  factory SyncPolicy.fromConfig(RemoteConfig c) {
    int clamp(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);
    return SyncPolicy(
      ttl: Duration(hours: clamp(c.intSetting('cache.catalog_ttl_hours', 12), 1, 24 * 14)),
      parallelCategories: clamp(c.intSetting('cache.sync_parallel_categories', 2), 1, 6),
      epgRetention: Duration(hours: clamp(c.intSetting('cache.epg_retention_hours', 48), 1, 24 * 14)),
    );
  }

  /// A category synced more recently than this is skipped (resume / no waste).
  final Duration ttl;

  /// Categories fetched at the same time (panels ban bursts; keep low).
  final int parallelCategories;

  /// This many failed categories in a row ⇒ the panel is down; stop.
  final int maxConsecutiveFailures;
  final Duration epgRetention;
}

enum SyncPhase { idle, categories, live, movies, series, done, stopped, failed }

@immutable
class SyncProgress {
  const SyncProgress({
    required this.panelId,
    required this.phase,
    this.done = 0,
    this.total = 0,
    this.items = 0,
    this.skipped = 0,
    this.failedCategories = 0,
    this.failure,
  });

  final String panelId;
  final SyncPhase phase;

  /// Categories finished / to do in the current phase.
  final int done;
  final int total;

  /// Items saved so far in this run.
  final int items;

  /// Categories skipped because they were still fresh.
  final int skipped;
  final int failedCategories;

  /// Why the run failed (auth / expired / panel down).
  final ProviderFailure? failure;

  bool get running => phase.index >= SyncPhase.categories.index && phase.index <= SyncPhase.series.index;

  SyncProgress copyWith({SyncPhase? phase, int? done, int? total, int? items, int? skipped, int? failedCategories, ProviderFailure? failure}) =>
      SyncProgress(
        panelId: panelId,
        phase: phase ?? this.phase,
        done: done ?? this.done,
        total: total ?? this.total,
        items: items ?? this.items,
        skipped: skipped ?? this.skipped,
        failedCategories: failedCategories ?? this.failedCategories,
        failure: failure ?? this.failure,
      );

  @override
  String toString() => 'sync $panelId ${phase.name} $done/$total items=$items skipped=$skipped failed=$failedCategories'
      '${failure == null ? '' : ' (${failure!.kind.name})'}';
}

/// Fills [CatalogStore] from a panel, category by category (Phase 6.2).
///
/// * categories first (Home can show rails at once), then live → movies →
///   series, a few categories at a time;
/// * resumable: every category records when it was synced; fresh ones are
///   skipped, so a run cut short continues where it stopped;
/// * login refused / expired / banned ⇒ stop at once; one bad category ⇒
///   skip it; many failures in a row ⇒ the panel is down, stop;
/// * categories the panel removed disappear with their items;
/// * cancellable at any point (app sent to background, panel removed).
class CatalogSyncer {
  CatalogSyncer({required this.store, this.policy = const SyncPolicy(), DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final CatalogStore store;

  /// Replaced when a new admin config arrives (used from the next category on).
  SyncPolicy policy;
  final DateTime Function() _clock;

  /// Latest progress per panel (screens listen).
  final ValueNotifier<Map<String, SyncProgress>> progress = ValueNotifier(const {});

  final _cancelled = <String>{};
  final _running = <String, Future<SyncProgress>>{};

  bool isRunning(String panelId) => _running.containsKey(panelId);

  /// Stops a running sync after the categories in flight.
  void cancel(String panelId) {
    if (_running.containsKey(panelId)) _cancelled.add(panelId);
  }

  void cancelAll() => _cancelled.addAll(_running.keys);

  /// Syncs one panel. A second call while it runs returns the same run.
  /// [force] ignores freshness (pull-to-refresh). [maxCategoriesPerKind]
  /// limits the run (tests / live checks only).
  Future<SyncProgress> sync(String panelId, ProviderAdapter adapter, {bool force = false, int? maxCategoriesPerKind}) {
    return _running[panelId] ??= _run(panelId, adapter, force, maxCategoriesPerKind).whenComplete(() {
      _running.remove(panelId);
      _cancelled.remove(panelId);
    });
  }

  Future<SyncProgress> _run(String panelId, ProviderAdapter adapter, bool force, int? limit) async {
    final sw = Stopwatch()..start();
    var p = SyncProgress(panelId: panelId, phase: SyncPhase.categories);
    void emit(SyncProgress next) {
      p = next;
      progress.value = {...progress.value, panelId: next};
    }

    emit(p);
    Diag.event('SYNC', 'sync $panelId start${force ? ' (forced)' : ''}');
    final caps = adapter.capabilities;
    final kinds = [
      if (caps.live) CatalogKind.live,
      if (caps.movies) CatalogKind.movie,
      if (caps.series) CatalogKind.series,
    ];

    try {
      // 1. Category lists (cheap; screens can show category rails right away).
      final cats = <CatalogKind, List<ProviderCategory>>{};
      for (final kind in kinds) {
        if (_stop(panelId)) return _finish(emit, p, SyncPhase.stopped, sw);
        final list = await _categories(adapter, kind);
        cats[kind] = list;
        await store.saveCategories(panelId, kind, list);
        final removed = await store.pruneMissingCategories(panelId, kind, {for (final c in list) c.id});
        await store.markSynced(panelId, '${kind.name}:categories', at: _clock(), count: list.length);
        Diag.event('SYNC', 'sync $panelId ${kind.name}: ${list.length} categories${removed > 0 ? ', $removed old items removed' : ''}');
      }

      // 2. Items, category by category.
      for (final kind in kinds) {
        final phase = switch (kind) {
          CatalogKind.live => SyncPhase.live,
          CatalogKind.movie => SyncPhase.movies,
          CatalogKind.series => SyncPhase.series,
        };
        var list = cats[kind] ?? const [];
        if (limit != null && list.length > limit) list = list.sublist(0, limit);
        emit(p.copyWith(phase: phase, done: 0, total: list.length));

        var next = 0;
        var consecutiveFailures = 0;
        ProviderFailure? fatal;

        Future<void> worker() async {
          while (fatal == null && !_stop(panelId)) {
            final i = next++;
            if (i >= list.length) return;
            final cat = list[i];
            final scope = '${kind.name}:cat:${cat.id}';
            final info = force ? null : await store.syncInfo(panelId, scope);
            if (info != null && _clock().difference(info.syncedAt) < policy.ttl) {
              emit(p.copyWith(done: p.done + 1, skipped: p.skipped + 1));
              continue;
            }
            try {
              final n = await _syncCategory(panelId, adapter, kind, cat.id, scope);
              consecutiveFailures = 0;
              emit(p.copyWith(done: p.done + 1, items: p.items + n));
            } on ProviderFailure catch (f) {
              if (_isFatal(f)) {
                fatal = f;
                return;
              }
              consecutiveFailures++;
              Diag.event('SYNC', 'sync $panelId $scope failed: ${f.kind.name} (${f.detail}) — skipped');
              emit(p.copyWith(done: p.done + 1, failedCategories: p.failedCategories + 1));
              if (consecutiveFailures >= policy.maxConsecutiveFailures) {
                fatal = ProviderFailure(f.kind, 'panel not answering: $consecutiveFailures categories failed in a row');
                return;
              }
            }
          }
        }

        await Future.wait([for (var w = 0; w < policy.parallelCategories; w++) worker()]);
        if (fatal != null) {
          emit(p.copyWith(phase: SyncPhase.failed, failure: fatal));
          Diag.event('SYNC', 'sync $panelId FAILED in ${sw.elapsedMilliseconds}ms: ${fatal!.kind.name} (${fatal!.detail}) — $p');
          return p;
        }
        if (_stop(panelId)) return _finish(emit, p, SyncPhase.stopped, sw);
      }

      await store.pruneEpg(panelId, _clock().subtract(policy.epgRetention));
      return _finish(emit, p, SyncPhase.done, sw);
    } on ProviderFailure catch (f) {
      emit(p.copyWith(phase: SyncPhase.failed, failure: f));
      Diag.event('SYNC', 'sync $panelId FAILED in ${sw.elapsedMilliseconds}ms: ${f.kind.name} (${f.detail})');
      return p;
    }
  }

  SyncProgress _finish(void Function(SyncProgress) emit, SyncProgress p, SyncPhase phase, Stopwatch sw) {
    final out = p.copyWith(phase: phase);
    emit(out);
    Diag.event('SYNC', 'sync ${p.panelId} ${phase.name} in ${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)}s: '
        '${out.items} items, ${out.skipped} fresh categories skipped, ${out.failedCategories} failed');
    return out;
  }

  bool _stop(String panelId) => _cancelled.contains(panelId);

  /// Login / subscription problems end the run; anything else is per category.
  static bool _isFatal(ProviderFailure f) =>
      f.kind == ProviderFailureKind.unauthorized ||
      f.kind == ProviderFailureKind.expired ||
      f.kind == ProviderFailureKind.banned ||
      f.kind == ProviderFailureKind.unsupported;

  static Future<List<ProviderCategory>> _categories(ProviderAdapter a, CatalogKind kind) => switch (kind) {
        CatalogKind.live => a.liveCategories(),
        CatalogKind.movie => a.movieCategories(),
        CatalogKind.series => a.seriesCategories(),
      };

  Future<int> _syncCategory(String panelId, ProviderAdapter a, CatalogKind kind, String catId, String scope) async {
    int? maxAdded(Iterable<int?> xs) {
      int? m;
      for (final x in xs) {
        if (x != null && (m == null || x > m)) m = x;
      }
      return m;
    }

    final int count;
    final int? newest;
    switch (kind) {
      case CatalogKind.live:
        final items = await a.liveChannels(categoryId: catId);
        await store.saveChannels(panelId, catId, items);
        count = items.length;
        newest = maxAdded(items.map((x) => x.addedSec));
      case CatalogKind.movie:
        final items = await a.movies(categoryId: catId);
        await store.saveMovies(panelId, catId, items);
        count = items.length;
        newest = maxAdded(items.map((x) => x.addedSec));
      case CatalogKind.series:
        final items = await a.series(categoryId: catId);
        await store.saveSeries(panelId, catId, items);
        count = items.length;
        newest = maxAdded(items.map((x) => x.addedSec));
    }
    await store.markSynced(panelId, scope, at: _clock(), count: count, maxAddedSec: newest);
    return count;
  }
}
