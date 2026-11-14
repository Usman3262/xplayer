import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/search/tv_search_screen.dart';
import '../widgets/focus_tile.dart';
import 'tv_ui.dart';

/// Shared page chrome: title + optional bilingual line + subtitle + search.
class TvPageHeader extends StatelessWidget {
  const TvPageHeader({
    super.key,
    required this.title,
    this.arabicTitle,
    this.titleAlt,
    this.subtitle,
    this.titleChip,
    this.countLabel,
    this.showSearch = false,
    this.trailing,
  });

  final String title;

  /// Optional secondary title (Figma bilingual / Arabic) beside the main title.
  final String? arabicTitle;
  /// Alias for [arabicTitle].
  final String? titleAlt;
  final String? subtitle;

  /// Optional count / status chip next to the title (e.g. "14 Titles").
  final String? titleChip;
  /// Alias for [titleChip].
  final String? countLabel;
  final bool showSearch;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ar = (arabicTitle ?? titleAlt ?? '').trim();
    final chip = (titleChip ?? countLabel ?? '').trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 22,
                        height: 1.15,
                      ),
                    ),
                    if (ar.isNotEmpty)
                      Text(
                        ar,
                        style: TvUi.titleArabic.copyWith(fontSize: 16),
                        textDirection: TextDirection.rtl,
                      ),
                    if (chip.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.12),
                          ),
                        ),
                        child: Text(
                          chip,
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                      ),
                  ],
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          ?trailing,
          if (showSearch) ...[
            const SizedBox(width: 12),
            FocusTile(
              borderRadius: 22,
              focusScale: 1.0,
              onTap: () => context.go(
                TvSearchScreen.searchPathFor(
                  GoRouterState.of(context).matchedLocation,
                ),
              ),
              child: Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.border),
                ),
                child: const Icon(Icons.search_rounded, size: 18),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
