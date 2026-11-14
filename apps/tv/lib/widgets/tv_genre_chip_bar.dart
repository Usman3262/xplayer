import 'package:design_system/design_system.dart' show AppColors, AppFonts;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'focus_tile.dart';
import 'tv_ui.dart';

/// Horizontal genre/category chips for Movies / Series / Search (screenshot
/// cyan filled pills).
class TvGenreChipBar extends StatelessWidget {
  const TvGenreChipBar({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
    this.escapeFirstChipToSidebar = true,
    this.icons = const {},
  });

  /// First entry should be `All` (or localized equivalent).
  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool escapeFirstChipToSidebar;

  /// Optional leading icon per chip index (e.g. the Sort chip).
  final Map<int, IconData> icons;

  static const _chipHeight = 34.0;
  static const _maxChipWidth = 220.0;

  @override
  Widget build(BuildContext context) {
    return FocusTraversalGroup(
      policy: ReadingOrderTraversalPolicy(),
      child: SizedBox(
        height: _chipHeight + 10,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          scrollCacheExtent: const ScrollCacheExtent.pixels(600),
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: labels.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final selected = i == selectedIndex;
            final label = labels[i];
            return FocusTile(
              escapeToSidebar: escapeFirstChipToSidebar && i == 0,
              escapeUpToSidebar: escapeFirstChipToSidebar && i == 0,
              borderRadius: 999,
              borderWidth: 2.5,
              focusScale: 1.0,
              // The blue selected chip ("All"): glass focus (client 12 Nov).
              glassFocus: selected,
              onTap: () => onSelected(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                height: _chipHeight,
                constraints: const BoxConstraints(maxWidth: _maxChipWidth),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                // Shared glass chip (Figma category pills); selected = cyan.
                decoration: TvGlassStyle.surface(
                  radius: BorderRadius.circular(999),
                  selected: selected,
                ),
                child: Center(
                  widthFactor: 1,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icons[i] != null) ...[
                        Icon(
                          icons[i],
                          size: 16,
                          color: selected ? Colors.black : AppColors.cyan,
                        ),
                        const SizedBox(width: 6),
                      ],
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: selected ? Colors.black : Colors.white,
                            fontWeight: AppFonts.control(FontWeight.w800),
                            fontSize: 12,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
