import 'dart:async';

import 'package:flutter/foundation.dart';

import '../backend/catalog_models.dart' show CatalogKind;
import '../backend/remote_config.dart';
import '../device/device_capabilities.dart' show DeviceTier;
import '../device/device_capabilities_store.dart';
import '../diag/diag.dart';
import '../providers/provider_adapter.dart';
import 'package:domain/domain.dart' show MediaKind;

import '../providers/provider_models.dart';
import 'adult.dart';
import 'catalog_store.dart';

/// How the sync behaves. Built-in defaults; admin config overrides
/// (App customization → Versions → Cache & refresh).
@immutable
class SyncPolicy {
  const SyncPolicy({
    this.ttl = const Duration(hours: 12),
    this.parallelCategories = 1,
    this.gap = const Duration(milliseconds: 300),
    this.maxConsecutiveFailures = 5,
    this.failureBackoff = const Duration(seconds: 5),
    this.epgRetention = const Duration(hours: 48),
    this.adultKeywords = AdultClassifier.defaultKeywords,
    this.cooldown = const Duration(minutes: 30),
    this.bulkMaxCategories = 200,
  });

  factory SyncPolicy.fromConfig(RemoteConfig c) {
    int clamp(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);
    return SyncPolicy(
      ttl: Duration(hours: clamp(c.intSetting('cache.catalog_ttl_hours', 12), 1, 24 * 14)),
      parallelCategories: clamp(c.intSetting('cache.sync_parallel_categories', 1), 1, 6),
      gap: Duration(milliseconds: clamp(c.intSetting('cache.sync_gap_ms', 300), 0, 5000)),
      epgRetention: Duration(hours: clamp(c.intSetting('cache.epg_retention_hours', 48), 1, 24 * 14)),
      adultKeywords: c.listSetting('content.adult_keywords', AdultClassifier.defaultKeywords),
      cooldown: Duration(minutes: clamp(c.intSetting('cache.sync_cooldown_min', 30), 1, 24 * 60)),
      bulkMaxCategories: _bulkLimitForDevice(),
    );
  }

  /// A category synced more recently than this is skipped (resume / no waste).
  final Duration ttl;

  /// Categories fetched at the same time (panels ban bursts; keep low).
  final int parallelCategories;

  /// Pause between two category requests of one worker. Real panels
  /// IP-block clients that sync too fast (user's line, 2026-11-15).
  final Duration gap;

  /// After a failed category, wait this × failures-in-a-row before the next.
  final Duration failureBackoff;

  /// This many failed categories in a row ⇒ the panel is down; stop.
  final int maxConsecutiveFailures;
  final Duration epgRetention;

  /// Category-name words that mark 18+ (admin `content.adult_keywords`).
  final List<String> adultKeywords;

  /// After the panel stopped answering / blocked us: no background sync for
  /// this long, even across app restarts (admin `cache.sync_cooldown_min`).
  final Duration cooldown;

  /// "bulkIfSmall": one request for the whole kind when the panel has at
  /// most this many categories of it (else category by category).
  final int bulkMaxCategories;

  /// A whole huge panel in one reply (e.g. 187k movies ≈ 77 MB of JSON) is
  /// fine on a phone with memory to spare, not on a low-end TV box.
  static int _bulkLimitForDevice() => switch (DeviceCapabilitiesStore.instance.current?.tier) {
        DeviceTier.low => 200,
        null => 200,
        _ => 5000,
      };
}

enum SyncPhase { idle, categories, items, done, stopped, failed }

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

  bool get running => phase == SyncPhase.categories || phase == SyncPhase.items;

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

  final _cancelled = <String, String>{};
  final _running = <String, Future<SyncProgress>>{};

  bool isRunning(String panelId) => _running.containsKey(panelId);

  /// Stops a running sync after the categories in flight.
  void cancel(String panelId, {String reason = 'cancelled'}) {
    if (_running.containsKey(panelId)) _cancelled[panelId] = reason;
  }

  void cancelAll({String reason = 'cancelled'}) {
    for (final id in _running.keys) {
      _cancelled[id] = reason;
    }
  }

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
    final cool = force ? null : await store.syncInfo(panelId, _cooldownScope);
    if (cool != null && _clock().difference(cool.syncedAt) < policy.cooldown) {
      final left = policy.cooldown - _clock().difference(cool.syncedAt);
      _cancelled[panelId] = 'panel stopped answering earlier, waiting ${left.inMinutes + 1} more min before syncing again';
      return _finish(emit, p, SyncPhase.stopped, sw);
    }
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
        final adult = AdultClassifier(policy.adultKeywords);
        bool isAdult(ProviderCategory c) => adult.isAdultCategory(c.name, panelFlag: c.adult);
        await store.saveCategories(panelId, kind, list, isAdult: isAdult);
        final adultCount = list.where(isAdult).length;
        if (adultCount > 0) Diag.event('SYNC', 'sync $panelId ${kind.name}: $adultCount adult (18+) categories, hidden behind the PIN');
        final removed = await store.pruneMissingCategories(panelId, kind, {for (final c in list) c.id});
        await store.markSynced(panelId, '${kind.name}:categories', at: _clock(), count: list.length);
        Diag.event('SYNC', 'sync $panelId ${kind.name}: ${list.length} categories${removed > 0 ? ', $removed old items removed' : ''}');
      }

      // 2. Items (titles; details come later / when opened), with the fewest
      //    requests the panel allows:
      //   a. Home warm-up: bulk kinds in ONE request each; per-category /
      //      on-demand kinds: their first categories;
      //   b. the rest of the per-category kinds: movies, series, live.
      //   On-demand kinds (Stalker VOD) stop after the warm-up; other
      //   categories load when the user opens them (priority lane).
      const warmUp = {CatalogKind.movie: 2, CatalogKind.series: 2, CatalogKind.live: 1};
      MediaKind mk(CatalogKind k) => switch (k) {
            CatalogKind.live => MediaKind.live,
            CatalogKind.movie => MediaKind.movie,
            CatalogKind.series => MediaKind.series,
          };
      final order = [
        for (final k in const [CatalogKind.movie, CatalogKind.series, CatalogKind.live])
          if (kinds.contains(k)) k,
      ];
      final lists = {
        for (final k in order)
          k: () {
            final l = cats[k] ?? const <ProviderCategory>[];
            return limit != null && l.length > limit ? l.sublist(0, limit) : l;
          }(),
      };
      bool bulk(CatalogKind k) => switch (caps.listsFor(mk(k))) {
            ListStrategy.bulk => limit == null,
            ListStrategy.bulkIfSmall => limit == null && (cats[k]?.length ?? 0) <= policy.bulkMaxCategories,
            _ => false,
          };
      // A null category = "the whole kind in one request".
      final work = <(CatalogKind, ProviderCategory?)>[
        for (final k in order)
          if (bulk(k)) (k, null) else ...lists[k]!.take(warmUp[k]!).map((c) => (k, c)),
        for (final k in order)
          if (!bulk(k) && caps.listsFor(mk(k)) != ListStrategy.onDemand)
            ...lists[k]!.skip(warmUp[k]!).map((c) => (k, c)),
      ];
      final bulkKinds = [for (final k in order) if (bulk(k)) k.name];
      final onDemand = [for (final k in order) if (caps.listsFor(mk(k)) == ListStrategy.onDemand) k.name];
      Diag.event('SYNC', 'sync $panelId plan: ${work.length} requests'
          '${bulkKinds.isEmpty ? '' : ' (${bulkKinds.join('/')} in one request each)'}'
          '${onDemand.isEmpty ? '' : '; ${onDemand.join('/')}: warm-up now, other categories when opened'}');
      emit(p.copyWith(phase: SyncPhase.items, done: 0, total: work.length));

      var next = 0;
      var consecutiveFailures = 0;
      ProviderFailure? fatal;

      Future<void> worker() async {
        while (fatal == null && !_stop(panelId)) {
          final i = next++;
          if (i >= work.length) return;
          final (kind, cat) = work[i];
          final scope = cat == null ? '${kind.name}:all' : '${kind.name}:cat:${cat.id}';
          final info = force ? null : await store.syncInfo(panelId, scope);
          if (info != null && _clock().difference(info.syncedAt) < policy.ttl) {
            emit(p.copyWith(done: p.done + 1, skipped: p.skipped + 1));
            continue;
          }
          if (policy.gap > Duration.zero) await Future<void>.delayed(policy.gap);
          if (_stop(panelId)) return;
          try {
            final n = cat == null
                ? await _syncAll(panelId, adapter, kind, cats[kind] ?? const [], scope)
                : await _syncCategory(panelId, adapter, kind, cat.id, scope);
            consecutiveFailures = 0;
            emit(p.copyWith(done: p.done + 1, items: p.items + n));
            if (p.done % 100 == 0) {
              Diag.event('SYNC', 'sync $panelId: ${p.done}/${p.total} categories, '
                  '${p.items} items so far (${(sw.elapsedMilliseconds / 1000).toStringAsFixed(0)}s)');
            }
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
            // Panel struggling: slow down before asking again.
            await Future<void>.delayed(policy.failureBackoff * consecutiveFailures);
          }
        }
      }

      await Future.wait([for (var w = 0; w < policy.parallelCategories; w++) worker()]);
      if (fatal != null) {
        if (_blocksUs(fatal!)) {
          await store.markSynced(panelId, _cooldownScope, at: _clock());
          Diag.event('SYNC', 'sync $panelId: panel not answering or blocking, no background sync for '
              '${policy.cooldown.inMinutes} min (also after app restarts)');
        }
        emit(p.copyWith(phase: SyncPhase.failed, failure: fatal));
        Diag.event('SYNC', 'sync $panelId FAILED in ${sw.elapsedMilliseconds}ms: ${fatal!.kind.name} (${fatal!.detail}) — $p');
        return p;
      }
      if (_stop(panelId)) return _finish(emit, p, SyncPhase.stopped, sw);

      await store.pruneEpg(panelId, _clock().subtract(policy.epgRetention));
      await store.clearSync(panelId, _cooldownScope);
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
    final why = phase == SyncPhase.stopped ? ' (${_cancelled[p.panelId] ?? 'cancelled'})' : '';
    Diag.event('SYNC', 'sync ${p.panelId} ${phase.name}$why in ${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)}s: '
        '${out.items} items, ${out.skipped} fresh categories skipped, ${out.failedCategories} failed');
    return out;
  }

  bool _stop(String panelId) => _cancelled.containsKey(panelId);

  static const _cooldownScope = 'panel:cooldown';

  /// The panel stopped answering us or refuses us now (not a subscription
  /// problem): back off for a while instead of hammering it on every start.
  static bool _blocksUs(ProviderFailure f) =>
      f.kind == ProviderFailureKind.network ||
      f.kind == ProviderFailureKind.timeout ||
      f.kind == ProviderFailureKind.rateLimited ||
      f.kind == ProviderFailureKind.server ||
      (f.kind == ProviderFailureKind.unauthorized && f.detail.startsWith('HTTP'));

  /// One request for the whole kind, split into its categories here.
  Future<int> _syncAll(String panelId, ProviderAdapter a, CatalogKind kind, List<ProviderCategory> cats, String scope) async {
    final sw = Stopwatch()..start();
    final known = {for (final c in cats) c.id};
    Map<String, List<T>> group<T>(List<T> items, String? Function(T) cat) {
      final out = <String, List<T>>{for (final id in known) id: <T>[]};
      for (final x in items) {
        final c = cat(x);
        if (c != null) (out[c] ??= <T>[]).add(x);
      }
      return out;
    }

    int count;
    int? newest;
    switch (kind) {
      case CatalogKind.live:
        final items = await a.liveChannels();
        for (final e in group(items, (x) => x.categoryId).entries) {
          await store.saveChannels(panelId, e.key, e.value);
        }
        count = items.length;
        newest = _max(items.map((x) => x.addedSec));
      case CatalogKind.movie:
        final items = await a.movies();
        for (final e in group(items, (x) => x.categoryId).entries) {
          await store.saveMovies(panelId, e.key, e.value);
        }
        count = items.length;
        newest = _max(items.map((x) => x.addedSec));
      case CatalogKind.series:
        final items = await a.series();
        for (final e in group(items, (x) => x.categoryId).entries) {
          await store.saveSeries(panelId, e.key, e.value);
        }
        count = items.length;
        newest = _max(items.map((x) => x.addedSec));
    }
    final at = _clock();
    for (final c in cats) {
      await store.markSynced(panelId, '${kind.name}:cat:${c.id}', at: at);
    }
    await store.markSynced(panelId, scope, at: at, count: count, maxAddedSec: newest);
    Diag.event('SYNC', 'sync $panelId ${kind.name}: all $count titles in one request (${sw.elapsedMilliseconds}ms), '
        'saved into ${cats.length} categories');
    return count;
  }

  static int? _max(Iterable<int?> xs) {
    int? m;
    for (final x in xs) {
      if (x != null && (m == null || x > m)) m = x;
    }
    return m;
  }

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
