import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../browse/kids_screen.dart';
import 'sports_screen.dart';

/// Bottom-nav slot 5: Sports when the subscription includes it; otherwise
/// Kids occupies that slot (client 20 Oct).
class SportsOrKidsBranch extends ConsumerWidget {
  const SportsOrKidsBranch({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sportsOn = ref.watch(sportsEnabledProvider).valueOrNull ?? false;
    if (sportsOn) return const SportsScreen();
    return const KidsScreen(asRootTab: true);
  }
}
