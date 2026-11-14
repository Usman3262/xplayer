import 'package:data/data.dart' show Diag;
import 'package:design_system/design_system.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/session_controller.dart';
import '../../widgets/category_channel_trails.dart';
import '../../widgets/main_app_bar.dart';
import 'match_centre_screen.dart';

/// Sports: categorical row trails of live sports networks / channels.
class SportsScreen extends ConsumerStatefulWidget {
  const SportsScreen({super.key});

  @override
  ConsumerState<SportsScreen> createState() => _SportsScreenState();
}

class _SportsScreenState extends ConsumerState<SportsScreen> {
  bool _shown = false;

  @override
  Widget build(BuildContext context) {
    // Nothing is loaded until the Sports tab is opened. The tab used to check
    // the shell's index once: a rebuild while another tab was showing (a
    // language switch rebuilds every tab) left an empty page, and opening
    // the tab did not rebuild it (iPhone, 17 Oct). TickerMode is on only for
    // the visible tab and rebuilds this screen when that changes.
    final shell = StatefulNavigationShell.maybeOf(context);
    if (TickerMode.valuesOf(context).enabled || shell == null) _shown = true;
    if (!_shown) return const Scaffold(body: SizedBox.shrink());

    final enabled = ref.watch(sportsEnabledProvider);
    final copy = AppCopy.ofLanguage(
      ref.watch(sessionProvider.select((s) => s.language)),
    );

    return enabled.when(
      loading: () => Scaffold(
        appBar: const MainAppBar(),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [AppShimmer.listRows()],
        ),
      ),
      error: (e, _) => Scaffold(
        appBar: const MainAppBar(),
        body: AppEmpty(
          icon: Icons.cloud_off_rounded,
          title: copy.couldNotLoad,
          actionLabel: copy.retry,
          onAction: () => ref.invalidate(sportsEnabledProvider),
        ),
      ),
      data: (on) {
        Diag.dev(
          'SPORTS_DATA mobileSportsScreen sportsEnabled=$on '
          '(channels tab only; no fixtures/lineups API)',
        );
        if (!on) {
          return Scaffold(
            appBar: const MainAppBar(),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  copy.sportsNotInPackage,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ),
          );
        }
        // Touch sportsProvider once so getSportsMatches Diag lines appear
        // in console during Sports tab QA.
        ref.watch(sportsProvider);
        return CategoryChannelTrailsScreen(
          kind: MediaKind.sports,
          eyebrow: copy.sports,
          searchHint: copy.searchSports,
          sportsOnly: true,
          // Client 20 Oct: schedules + lineups (shown when the server has it).
          header: const MatchCentreEntry(),
        );
      },
    );
  }
}
