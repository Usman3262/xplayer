import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session_controller.dart';
import '../../widgets/main_app_bar.dart';

class PrivacyPolicyScreen extends ConsumerWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = AppLocale.resolve(
      ref.watch(sessionProvider.select((s) => s.language)),
    );
    return Scaffold(
      appBar: const MainAppBar(showBack: true),
      body: AppLegalDocumentView.privacy(lang: lang),
    );
  }
}
