import 'package:flutter/foundation.dart';

import '../../backend/remote_config.dart';
import '../../diag/diag.dart';
import '../m3u/m3u_adapter.dart';
import '../provider_adapter.dart';
import '../provider_http.dart';
import '../provider_models.dart';
import '../stalker/stalker_adapter.dart';
import '../xtream/xtream_adapter.dart';
import 'connection_store.dart';
import 'panel_connection.dart';

/// Registers every adapter with limits from the admin config
/// (`providers.*` timeouts/concurrency, `player.live_format`). Call at start
/// and whenever a new config is applied.
void registerProviderAdapters(RemoteConfig config, {String timezone = 'UTC'}) {
  final limits = ProviderLimits.fromConfig(config);
  XtreamAdapter.register(limits: limits, liveFormat: config.stringSetting('player.live_format', 'ts'));
  M3uAdapter.register(limits: limits);
  StalkerAdapter.register(limits: limits, timezone: timezone);
}

/// Saved panels on this device: connect, re-check, primary, enable/disable,
/// rename, remove. Spec §3.5: a panel is re-checked, never assumed active.
///
/// Admin control: which panel types may be added (`onboarding_panel_types`,
/// via [config]) and how many panels (`providers.max_connections`).
class ConnectionManager {
  ConnectionManager({
    ConnectionStore? store,
    ProviderAdapter Function(ProviderCredentials)? createAdapter,
    RemoteConfig Function()? config,
    DateTime Function()? clock,
    this.onRemoved,
  })  : _store = store ?? ConnectionStore(),
        _create = createAdapter ?? ProviderAdapterFactory.create,
        _config = config ?? (() => RemoteConfig.empty),
        _clock = clock ?? DateTime.now;

  final ConnectionStore _store;
  final ProviderAdapter Function(ProviderCredentials) _create;
  final RemoteConfig Function() _config;
  final DateTime Function() _clock;

  /// Called after a panel is removed (e.g. delete its local catalog).
  final Future<void> Function(String panelId)? onRemoved;

  /// Current panels (primary first). Screens listen to this.
  final ValueNotifier<List<PanelConnection>> connections = ValueNotifier(const []);

  final _adapters = <String, ProviderAdapter>{};
  bool _loaded = false;

  PanelConnection? get primary => connections.value.where((c) => c.isPrimary && c.enabled).firstOrNull;

  Future<List<PanelConnection>> load() async {
    if (!_loaded) {
      _set(await _store.loadAll());
      _loaded = true;
    }
    return connections.value;
  }

  /// Max panels a user may save (admin: Access → panel limit).
  int get maxPanels => _config().intSetting('providers.max_connections', 5).clamp(1, 50);

  /// Panel types the admin has switched on. Empty config (first start,
  /// offline) → every type the app knows.
  Set<ProviderKind> get allowedKinds {
    final types = _config().panelTypes;
    if (types.isEmpty) return ProviderKind.values.toSet();
    return types.map((t) => ProviderKind.fromKey(t.key)).whereType<ProviderKind>().toSet();
  }

  /// MAC this device shows for Stalker portals (created once).
  Future<String> deviceMac() => _store.deviceMac();
  Future<String?> setDeviceMac(String mac) => _store.setDeviceMac(mac);

  /// "Test connection": logs in, saves nothing. Throws [ProviderFailure].
  Future<ProviderAccount> test(ProviderCredentials credentials) async {
    _checkAllowed(credentials);
    final a = _create(credentials);
    try {
      return await a.authenticate();
    } finally {
      a.dispose();
    }
  }

  /// "Connect": logs in, then saves. The same panel added again (same
  /// server+user / playlist / portal+MAC) updates the saved one instead of
  /// making a duplicate. First panel becomes primary. Throws
  /// [ProviderFailure] and saves nothing when the login fails.
  Future<PanelConnection> connect(ProviderCredentials credentials, {String? name, bool makePrimary = false}) async {
    await load();
    _checkAllowed(credentials);
    final existing = await _findSame(credentials);
    if (existing == null && connections.value.length >= maxPanels) {
      throw ProviderFailure(ProviderFailureKind.invalidInput, 'max panels $maxPanels');
    }
    Diag.panel('connect ${credentials.kind.name} → ${describeInput(credentials)}');
    final sw = Stopwatch()..start();
    final adapter = _create(credentials);
    final ProviderAccount account;
    try {
      account = await adapter.authenticate();
    } on ProviderFailure catch (f) {
      Diag.panel('connect ${credentials.kind.name} FAILED in ${sw.elapsedMilliseconds}ms: ${f.kind.name} (${f.detail})');
      adapter.dispose();
      rethrow;
    } catch (e) {
      Diag.panel('connect ${credentials.kind.name} CRASHED in ${sw.elapsedMilliseconds}ms: ${e.runtimeType}: $e');
      adapter.dispose();
      rethrow;
    }
    Diag.panel('connect ${credentials.kind.name} OK in ${sw.elapsedMilliseconds}ms: ${account.status.name}, '
        'expires ${account.expiresAt?.toIso8601String() ?? 'never/unknown'}, max streams ${account.maxConnections ?? '?'}, '
        'formats ${account.allowedOutputFormats}');
    final now = _clock();
    final id = existing?.id ?? _store.newId();
    await _store.saveCredentials(id, credentials);
    _adapters.remove(id)?.dispose();
    _adapters[id] = adapter;

    final isFirst = connections.value.where((c) => c.enabled).isEmpty;
    final saved = (existing ??
            PanelConnection(
              id: id,
              kind: credentials.kind,
              name: credentials.safeLabel,
              status: ConnectionStatus.pending,
              addedAt: now,
            ))
        .copyWith(
      name: (name ?? '').trim().isEmpty ? null : name!.trim(),
      status: account.status,
      expiresAt: account.expiresAt,
      clearExpiry: account.expiresAt == null,
      lastCheckedAt: now,
      enabled: true,
      clearFailure: true,
      maxConnections: account.maxConnections,
    );
    var list = [for (final c in connections.value) if (c.id != id) c, saved];
    if (makePrimary || isFirst || existing?.isPrimary == true) list = _withPrimary(list, id);
    await _persist(list);
    return connections.value.firstWhere((c) => c.id == id);
  }

  /// Re-check one panel (app start, pull to refresh). Never throws: the
  /// result is the panel's new status.
  Future<PanelConnection?> recheck(String id) async {
    await load();
    final c = _byId(id);
    if (c == null) return null;
    if (!c.enabled) return c;
    final now = _clock();
    PanelConnection next;
    try {
      final account = await (await adapterFor(id))!.authenticate();
      next = c.copyWith(
        status: account.status,
        expiresAt: account.expiresAt,
        clearExpiry: account.expiresAt == null,
        lastCheckedAt: now,
        clearFailure: true,
        maxConnections: account.maxConnections,
      );
    } on ProviderFailure catch (f) {
      Diag.panel('recheck ${c.kind.name} "${c.name}" → ${f.status.name} (${f.kind.name}: ${f.detail})');
      next = c.copyWith(status: f.status, lastCheckedAt: now, lastFailure: f.kind.name);
    } catch (_) {
      next = c.copyWith(
        status: ConnectionStatus.invalidConfiguration,
        lastCheckedAt: now,
        lastFailure: 'credentials',
      );
    }
    await _persist([for (final x in connections.value) x.id == id ? next : x]);
    return next;
  }

  /// Re-checks every enabled panel in parallel.
  Future<void> recheckAll() async {
    await load();
    await Future.wait([for (final c in connections.value.where((c) => c.enabled)) recheck(c.id)]);
  }

  /// Adapter for a saved panel (credentials opened from secure storage).
  Future<ProviderAdapter?> adapterFor(String id) async {
    final cached = _adapters[id];
    if (cached != null) return cached;
    final creds = await _store.loadCredentials(id);
    if (creds == null) return null;
    return _adapters[id] = _create(creds);
  }

  Future<void> setPrimary(String id) async {
    await load();
    final c = _byId(id);
    if (c == null || !c.enabled) return;
    await _persist(_withPrimary(connections.value, id));
  }

  /// Disabled panels are kept (with credentials) but not used or checked.
  Future<void> setEnabled(String id, bool enabled) async {
    await load();
    final c = _byId(id);
    if (c == null || c.enabled == enabled) return;
    var list = [
      for (final x in connections.value)
        x.id == id
            ? x.copyWith(
                enabled: enabled,
                isPrimary: enabled ? x.isPrimary : false,
                status: enabled ? ConnectionStatus.pending : ConnectionStatus.disabled,
              )
            : x,
    ];
    if (!enabled) {
      _adapters.remove(id)?.dispose();
      if (c.isPrimary) list = _promoteNext(list);
    } else if (list.where((x) => x.enabled && x.isPrimary).isEmpty) {
      list = _withPrimary(list, id);
    }
    await _persist(list);
    if (enabled) await recheck(id);
  }

  Future<void> rename(String id, String name) async {
    await load();
    final n = name.trim();
    if (n.isEmpty || _byId(id) == null) return;
    await _persist([for (final x in connections.value) x.id == id ? x.copyWith(name: n) : x]);
  }

  /// Removes the panel and its credentials from the device.
  Future<void> remove(String id) async {
    await load();
    final c = _byId(id);
    if (c == null) return;
    _adapters.remove(id)?.dispose();
    await _store.deleteCredentials(id);
    var list = [for (final x in connections.value) if (x.id != id) x];
    if (c.isPrimary) list = _promoteNext(list);
    await _persist(list);
    try {
      await onRemoved?.call(id);
    } catch (e) {
      Diag.panel('cleanup after removing panel failed: ${e.runtimeType}');
    }
  }

  /// Catalog sync finished (Phase 6).
  Future<void> markSynced(String id) async {
    await load();
    await _persist([for (final x in connections.value) x.id == id ? x.copyWith(lastSyncAt: _clock()) : x]);
  }

  /// What the app understood from the form (scheme/host/port/path), no secrets.
  static String describeInput(ProviderCredentials c) {
    String u(Uri? x, String raw) => x == null
        ? 'INVALID URL (${raw.trim().length} chars, starts "${raw.trim().length > 12 ? raw.trim().substring(0, 12) : raw.trim()}")'
        : Diag.panelUrl(x);
    return switch (c) {
      XtreamCredentials x => 'server ${u(x.baseUri, x.server)}, username ${x.username.trim().length} chars, '
          'password ${x.password.length} chars${x.username != x.username.trim() ? ' (username had spaces, trimmed)' : ''}'
          '${x.password != x.password.trim() ? ' (password has leading/trailing spaces!)' : ''}',
      M3uCredentials m => 'playlist ${u(m.playlistUri, m.url)}${(m.epgUrl ?? '').isEmpty ? '' : ', epg set'}',
      StalkerCredentials s => 'portal ${u(s.portalUri, s.portal)}, mac ${s.normalizedMac == null ? 'INVALID' : 'ok'}',
    };
  }

  void dispose() {
    for (final a in _adapters.values) {
      a.dispose();
    }
    _adapters.clear();
  }

  // ── internals ────────────────────────────────────────────────────────────

  void _checkAllowed(ProviderCredentials c) {
    if (!allowedKinds.contains(c.kind)) {
      throw ProviderFailure(ProviderFailureKind.unsupported, '${c.kind.name} off');
    }
  }

  PanelConnection? _byId(String id) => connections.value.where((c) => c.id == id).firstOrNull;

  Future<PanelConnection?> _findSame(ProviderCredentials c) async {
    final key = _sameKey(c);
    for (final x in connections.value.where((x) => x.kind == c.kind)) {
      final saved = await _store.loadCredentials(x.id);
      if (saved != null && _sameKey(saved) == key) return x;
    }
    return null;
  }

  static String _sameKey(ProviderCredentials c) => switch (c) {
        XtreamCredentials x => '${x.baseUri?.host}:${x.baseUri?.port}|${x.username.trim().toLowerCase()}',
        M3uCredentials m => '${m.playlistUri}',
        StalkerCredentials s => '${s.portalUri?.host}:${s.portalUri?.port}|${s.normalizedMac}',
      };

  static List<PanelConnection> _withPrimary(List<PanelConnection> list, String id) =>
      [for (final c in list) c.copyWith(isPrimary: c.id == id)];

  static List<PanelConnection> _promoteNext(List<PanelConnection> list) {
    final next = list.where((c) => c.enabled).firstOrNull;
    return next == null ? [for (final c in list) c.copyWith(isPrimary: false)] : _withPrimary(list, next.id);
  }

  Future<void> _persist(List<PanelConnection> list) async {
    await _store.saveAll(list);
    _set(list);
  }

  void _set(List<PanelConnection> list) {
    final sorted = [...list]..sort((a, b) {
        if (a.isPrimary != b.isPrimary) return a.isPrimary ? -1 : 1;
        if (a.enabled != b.enabled) return a.enabled ? -1 : 1;
        return a.addedAt.compareTo(b.addedAt);
      });
    connections.value = List.unmodifiable(sorted);
  }
}
