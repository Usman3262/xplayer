import 'dart:async';

/// Watches the package catalog version (`GET /catalog/version`) and reports
/// when it changes, so apps can tell the user that new content is available
/// and reload it without a reinstall, clearing data or signing out.
///
/// The backend bumps the version when a package changes in NEO / the Control
/// Panel or when the 12-hour content sync (or "Refresh now") finds changes.
class CatalogVersionWatcher {
  CatalogVersionWatcher(
    this._fetch, {
    this.interval = const Duration(minutes: 5),
  });

  final Future<String?> Function() _fetch;
  final Duration interval;

  String? _version;
  Timer? _timer;
  bool _busy = false;
  final _changes = StreamController<String>.broadcast();

  /// Emits the new version each time it differs from the last seen one.
  /// The first version seen after [start] or [reset] is only remembered.
  Stream<String> get changes => _changes.stream;

  String? get version => _version;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => unawaited(check()));
    unawaited(check());
  }

  /// Returns true when the version changed since the last check.
  Future<bool> check() async {
    if (_busy) return false;
    _busy = true;
    try {
      final v = await _fetch();
      if (v == null || v.isEmpty) return false;
      final before = _version;
      _version = v;
      if (before != null && before != v) {
        if (!_changes.isClosed) _changes.add(v);
        return true;
      }
      return false;
    } catch (_) {
      return false;
    } finally {
      _busy = false;
    }
  }

  /// Forget the last version (sign-out / profile or package change).
  void reset() => _version = null;

  void dispose() {
    _timer?.cancel();
    unawaited(_changes.close());
  }
}
