import 'dart:async';

import 'package:data/data.dart' show Diag;
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'tv_locale.dart';

import 'providers.dart';
import 'tv_session.dart';

/// Package / catalog changes reach the app (client 16 Oct: "changes made to
/// packages in the Control Panel are not reflected"). The backend bumps a
/// catalog version per package on every package update or refresh; the app
/// used to keep its in-memory catalog until it was restarted. Now it checks
/// the version at start, on return to the app and every 5 minutes, and
/// reloads the catalog when it changed.
class TvCatalogSync {
  TvCatalogSync(this._ref);

  final WidgetRef _ref;
  String? _version;
  Timer? _timer;
  bool _busy = false;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 5), (_) => check());
    unawaited(check());
  }

  Future<void> check() async {
    if (_busy) return;
    final session = _ref.read(tvSessionProvider);
    if (!session.loggedIn) return;
    _busy = true;
    try {
      final v = await _ref
          .read(tvMediaRepositoryProvider)
          .extras
          .catalogVersion();
      if (v == null) return;
      final before = _version;
      _version = v;
      if (before != null && before != v) {
        // Client 2 Nov: tell the user new content is available and let
        // them refresh from the notice (no reinstall, no sign-out).
        Diag.dev('CATALOG version $before -> $v: update available');
        _ref.read(tvCatalogUpdateProvider.notifier).state = v;
      }
    } finally {
      _busy = false;
    }
  }

  void dispose() => _timer?.cancel();
}


/// Pending catalog version (new content available), or null.
final tvCatalogUpdateProvider = StateProvider<String?>((ref) => null);

/// Applies a waiting catalog version: a new repository, so the lists load
/// the new content. Called when a section is opened or the app returns to the
/// front, never while the user is on a list (client 5 Nov, LG: a refresh under
/// the cursor looked like "the whole page reloads").
void applyPendingCatalogUpdate(WidgetRef ref) {
  if (ref.read(tvCatalogUpdateProvider) == null) return;
  ref.read(tvCatalogUpdateProvider.notifier).state = null;
  ref.read(catalogEpochProvider.notifier).state++;
}

/// Short "new content" notice over the page (as on LG 6.1.28): it never takes
/// the remote's focus, has no button, does not push the page down and hides
/// after 6 s. The new content shows when a section is opened.
class TvContentUpdateBanner extends ConsumerStatefulWidget {
  const TvContentUpdateBanner({super.key});

  @override
  ConsumerState<TvContentUpdateBanner> createState() => _TvContentUpdateBannerState();
}

class _TvContentUpdateBannerState extends ConsumerState<TvContentUpdateBanner> {
  bool _show = false;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    ref.listenManual<String?>(tvCatalogUpdateProvider, (prev, next) {
      if (next == null || next == prev) return;
      _hide?.cancel();
      setState(() => _show = true);
      _hide = Timer(const Duration(seconds: 6), () {
        if (mounted) setState(() => _show = false);
      });
    });
  }

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return const SizedBox.shrink();
    final ar = AppLocale.isArabic(ref.watch(tvLanguageProvider));
    return ExcludeFocus(
      child: IgnorePointer(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 360),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xEB0A1620),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.cyan.withValues(alpha: 0.45)),
            boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 30, offset: Offset(0, 10))],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.new_releases_rounded, color: AppColors.cyan, size: 18),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  ar ? 'محتوى جديد متاح — يظهر عند فتح القسم أو من الإعدادات › تحديث المحتوى' : 'New content available — it shows when you open a section, or Settings › Refresh content',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, height: 1.3),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
