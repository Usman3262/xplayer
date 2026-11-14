import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session_controller.dart';
import '../../widgets/main_app_bar.dart';

/// Clips stay out of the main app until the feed ships. Settings opens this.
class ClipsSoonScreen extends ConsumerWidget {
  const ClipsSoonScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = AppCopy.ofLanguage(
      ref.watch(sessionProvider.select((s) => s.language)),
    );
    return Scaffold(
      appBar: const MainAppBar(showBack: true),
      body: AppComingSoon(
        title: copy.clipsComingSoon,
        subtitle: copy.clipsComingSoonHint,
      ),
    );
  }
}
