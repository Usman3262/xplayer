import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session_controller.dart';
import '../../widgets/main_app_bar.dart';

class LanguageScreen extends ConsumerWidget {
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final copy = AppCopy.ofLanguage(session.language);
    final selected = AppLocale.normalize(session.language);

    return Scaffold(
      appBar: const MainAppBar(showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            copy.language,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22),
          ),
          const SizedBox(height: 8),
          Text(
            copy.languageHint,
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          Center(
            child: AppLanguageToggle(
              language: session.language,
              compact: false,
              onChanged: (v) =>
                  ref.read(sessionProvider.notifier).setLanguage(v),
            ),
          ),
          const SizedBox(height: 16),
          ...AppLocale.allLabels.map(
            (l) => RadioListTile<String>(
              value: l,
              groupValue: selected,
              activeColor: AppColors.cyan,
              title: Text(l),
              subtitle: Text(
                switch (AppLocale.resolve(l)) {
                  AppLang.en => 'English',
                  AppLang.ar => 'Arabic · العربية',
                  AppLang.ur => 'English',
                },
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              onChanged: (v) {
                if (v != null) {
                  ref.read(sessionProvider.notifier).setLanguage(v);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
