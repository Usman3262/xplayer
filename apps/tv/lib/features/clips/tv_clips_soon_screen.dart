import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tv_locale.dart';
import '../../widgets/tv_page_header.dart';

/// Clips stay out of the main app until the feed ships. Settings opens this.
class TvClipsSoonScreen extends ConsumerWidget {
  const TvClipsSoonScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = AppCopy.ofLanguage(ref.watch(tvLanguageProvider));
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TvPageHeader(
            title: copy.clips,
            titleAlt: 'مقاطع',
            subtitle: copy.clipsComingSoonHint,
            countLabel: copy.comingSoon,
            showSearch: false,
          ),
          Expanded(
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 520),
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: const Color(0xFF111622),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                child: AppEmpty(
                  title: copy.clipsComingSoon,
                  subtitle: copy.clipsComingSoonHint,
                  icon: Icons.movie_filter_rounded,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
