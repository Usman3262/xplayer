import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/tv_locale.dart';
import '../../widgets/focus_tile.dart';

/// Logged-out legal pages for TV login footer (Task #143 #4).
class TvLegalScreen extends ConsumerWidget {
  const TvLegalScreen({super.key, required this.kind});

  /// `terms` | `privacy`
  final String kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = AppCopy.ofLanguage(ref.watch(tvLanguageProvider));
    final isPrivacy = kind == 'privacy';
    final title = isPrivacy ? copy.privacyPolicy : copy.termsOfUse;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(48, 24, 48, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  FocusTile(
                    autofocus: true,
                    borderRadius: 10,
                    onTap: () {
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.go('/login');
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.arrow_back_rounded),
                          const SizedBox(width: 8),
                          Text(copy.playbackBack),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  child: isPrivacy
                      ? AppLegalDocumentView.privacy(lang: copy.lang)
                      : AppLegalDocumentView.terms(lang: copy.lang),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
