import 'dart:async';

import 'package:data/data.dart' show CatalogVersionWatcher, Diag;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';
import 'session_controller.dart';

/// True while a newer package catalog is waiting; the app shows a "New
/// content available" banner with Refresh (client: notify, then refresh from
/// the notification, no reinstall / logout / new store release).
final contentUpdatePendingProvider = StateProvider<bool>((ref) => false);

/// Reload every catalog list now (new repository, empty caches).
void refreshCatalogNow(WidgetRef ref) {
  ref.read(contentUpdatePendingProvider.notifier).state = false;
  ref.read(catalogEpochProvider.notifier).state++;
  ref.invalidate(homeFeedProvider);
  ref.invalidate(moviesProvider);
  ref.invalidate(seriesProvider);
}

/// Package / catalog changes reach the app (client 16 Oct and 2 Nov: changes
/// made in NEO / the Control Panel must show up). The backend bumps a catalog
/// version per package on every package update, content sync or refresh.
/// The app checks it at start, on return to the app and every 5 minutes;
/// on a change it shows the banner instead of reloading behind the user.
class CatalogSync {
  CatalogSync(this._ref);

  final WidgetRef _ref;
  late final CatalogVersionWatcher _watcher = CatalogVersionWatcher(_fetch);
  StreamSubscription<String>? _sub;

  Future<String?> _fetch() async {
    if (!_ref.read(sessionProvider).isLoggedIn) return null;
    return _ref.read(mediaRepositoryProvider).extras.catalogVersion();
  }

  void start() {
    _sub ??= _watcher.changes.listen((v) {
      Diag.dev('CATALOG version changed -> $v: banner');
      _ref.read(contentUpdatePendingProvider.notifier).state = true;
    });
    _watcher.start();
  }

  Future<void> check() => _watcher.check();

  void dispose() {
    unawaited(_sub?.cancel());
    _watcher.dispose();
  }
}
