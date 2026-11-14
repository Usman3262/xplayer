import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'focus_tile.dart';

/// Shared TV sizes, so every screen has the same rhythm (Netflix-style:
/// compact controls, generous but consistent gaps). Units are logical
/// pixels on a 960×540 TV canvas.
abstract final class TvUi {
  static const pageGutter = 40.0;
  static const sectionGap = 22.0;
  static const rowGap = 12.0;
  static const buttonHeight = 36.0;
  static const buttonGap = 10.0;
  static const radius = 10.0;
  static const cardRadius = 14.0;
  static const focusGlow = Color(0x6600C8FF);

  // Explicit white + shadow: without a colour it inherited a muted grey and
  // the hero title was hard to read from the sofa (client 19 Oct).
  static final titleXL = TextStyle(
    color: AppColors.textPrimary,
    fontWeight: FontWeight.w900,
    fontSize: 40,
    height: 1.02,
    letterSpacing: 0.4,
    shadows: [Shadow(color: Color(0xCC000000), blurRadius: 12)],
  );
  static final titleArabic = TextStyle(
    color: AppColors.cyan,
    fontWeight: FontWeight.w700,
    fontSize: 20,
    height: 1.2,
  );
  static final meta = TextStyle(
    color: AppColors.textSecondary,
    fontSize: 13,
    fontWeight: FontWeight.w600,
  );
  static const body = TextStyle(
    color: Color(0xFFD5DBE4),
    fontSize: 13,
    height: 1.45,
  );
  static const section = TextStyle(
    fontWeight: FontWeight.w800,
    fontSize: 16,
  );
  static final eyebrow = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w800,
    letterSpacing: 1.1,
    color: AppColors.textSecondary,
  );
}

enum TvPillTone { cyan, magenta, gold, live, muted, success }

/// Compact pill badge used across browse / live / settings screenshots.
class TvPill extends StatelessWidget {
  const TvPill(
    this.label, {
    super.key,
    this.tone = TvPillTone.cyan,
    this.icon,
    this.compact = false,
  });

  final String label;
  final TvPillTone tone;
  final IconData? icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg) = switch (tone) {
      TvPillTone.cyan => (AppColors.cyan, Colors.black),
      TvPillTone.magenta => (AppColors.magenta, Colors.white),
      TvPillTone.gold => (AppColors.gold, Colors.black),
      TvPillTone.live => (const Color(0xFFE91E63), Colors.white),
      TvPillTone.success => (const Color(0xFF22C55E), Colors.black),
      TvPillTone.muted => (
          Colors.white.withValues(alpha: 0.10),
          AppColors.textSecondary,
        ),
    };
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 10,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: compact ? 10 : 12, color: fg),
            SizedBox(width: compact ? 3 : 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w900,
              fontSize: compact ? 9 : 10,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

/// Horizontal segmented control (Appearance / filters screenshots).
class TvSegmentedControl extends StatelessWidget {
  const TvSegmentedControl({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelect,
    this.autofocusFirst = false,
    this.stopDown = false,
  });

  final List<String> options;
  final String selected;
  final ValueChanged<String> onSelect;
  final bool autofocusFirst;

  /// The last control of its page: Down stays here.
  final bool stopDown;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < options.length; i++)
            FocusTile(
              autofocus: autofocusFirst && i == 0,
              borderRadius: 999,
              borderWidth: 2,
              onKeyFirst: stopDown
                  ? (e) => e is! KeyUpEvent &&
                          e.logicalKey == LogicalKeyboardKey.arrowDown
                      ? KeyEventResult.handled
                      : KeyEventResult.ignored
                  : null,
              onTap: () => onSelect(options[i]),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: options[i] == selected
                      ? AppColors.cyan
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  options[i],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: options[i] == selected
                        ? Colors.black
                        : Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 10,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Bottom status strip used on Live / Search / Settings previews.
class TvStatusFooter extends StatelessWidget {
  const TvStatusFooter({
    super.key,
    required this.left,
    this.right,
  });

  final String left;
  final String? right;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: AppColors.cyan,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              left,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w700,
                fontSize: 10,
                letterSpacing: 0.4,
              ),
            ),
          ),
          if ((right ?? '').trim().isNotEmpty) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                right!.trim(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: TextStyle(
                  color: AppColors.cyan,
                  fontWeight: FontWeight.w800,
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Tiny skeleton cards for Home Preview panes.
class TvPreviewRailSkeleton extends StatelessWidget {
  const TvPreviewRailSkeleton({
    super.key,
    required this.title,
    this.count = 4,
    this.rowIndex,
  });

  final String title;
  final int count;
  final int? rowIndex;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: AppColors.cyan,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            if (rowIndex != null)
              Text(
                'ROW $rowIndex',
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w800,
                  color: Colors.white.withValues(alpha: 0.35),
                  letterSpacing: 0.6,
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (var j = 0; j < count; j++)
              Expanded(
                child: Container(
                  height: 32,
                  margin: EdgeInsetsDirectional.only(end: j == count - 1 ? 0 : 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF152033),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Compact action button. Primary = brand fill; secondary = translucent.
class TvButton extends StatelessWidget {
  const TvButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.primary = false,
    this.selected = false,
    this.autofocus = false,
    this.escapeUpToSidebar = false,
    this.escapeToSidebar = false,
    this.scrollToTopOnFocus = false,
    this.focusNode,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool primary;
  final bool selected;
  final bool autofocus;
  final bool escapeUpToSidebar;
  final bool escapeToSidebar;
  final bool scrollToTopOnFocus;

  /// Lets a caller move focus here (e.g. the reminder banner).
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final fg = primary ? Colors.black : Colors.white;
    final bg = primary
        ? AppColors.cyan
        : selected
            ? AppColors.cyan.withValues(alpha: 0.18)
            : Colors.white.withValues(alpha: 0.10);
    return FocusTile(
      autofocus: autofocus,
      focusNode: focusNode,
      escapeUpToSidebar: escapeUpToSidebar,
      escapeToSidebar: escapeToSidebar,
      scrollToTopOnFocus: scrollToTopOnFocus,
      borderRadius: TvUi.radius + 4,
      borderWidth: 2.5,
      ringColor: primary ? Colors.white : null,
      // Blue Watch Now: glass focus (client 12 Nov).
      glassFocus: primary,
      onTap: onTap,
      child: Container(
        height: TvUi.buttonHeight,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: primary
            ? BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(TvUi.radius + 2),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.cyan.withValues(alpha: 0.35),
                    blurRadius: 14,
                  ),
                ],
              )
            // Secondary actions: shared glass surface (Figma My List /
            // Details & Specs); selected keeps a cyan rim, not a full fill.
            : TvGlassStyle.surface(
                radius: BorderRadius.circular(TvUi.radius + 2),
              ).copyWith(
                border: selected
                    ? Border.all(color: AppColors.cyan, width: 1)
                    : null,
              ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 18,
                color: selected && !primary ? AppColors.cyan : fg,
              ),
              const SizedBox(width: 6),
            ],
            // Shrinks to fit a narrow slot instead of being cut off
            // ("Watch Fullscree" on Live TV, 19 Oct).
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    color: fg,
                    fontWeight: AppFonts.control(FontWeight.w700),
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Text tabs (seasons, filters): selected is bold with an underline — or filled
/// cyan pill when [filled] is true (search / season screenshot style).
/// Shared TV "glass" surface (Figma TV v2: translucent fill, 1 px light rim,
/// soft shadow). Gradient + border only — no BackdropFilter blur, which is too
/// heavy for living-room SoCs. Focus stays the FocusTile cyan ring; selected
/// items fill cyan.
/// Same glass as the phone apps ([AppGlass]).
abstract final class TvGlassStyle {
  static BoxDecoration surface({
    required BorderRadius radius,
    bool selected = false,
    bool circle = false,
  }) =>
      AppGlass.surface(radius: radius, selected: selected, circle: circle);
}

class TvTextTabs extends StatelessWidget {
  const TvTextTabs({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelect,
    this.selectedFocusNode,
    this.filled = false,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;
  final FocusNode? selectedFocusNode;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: filled ? 40 : 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: labels.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final on = i == selected;
          return FocusTile(
            focusNode: on ? selectedFocusNode : null,
            borderRadius: filled ? 999 : 8,
            borderWidth: 2.5,
            onTap: () => onSelect(i),
            child: filled
                ? AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: on ? AppColors.cyan : Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: on
                            ? AppColors.cyan
                            : Colors.white.withValues(alpha: 0.12),
                      ),
                      boxShadow: on
                          ? [
                              BoxShadow(
                                color: AppColors.cyan.withValues(alpha: 0.35),
                                blurRadius: 12,
                              ),
                            ]
                          : null,
                    ),
                    child: Text(
                      labels[i],
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: on ? Colors.black : Colors.white,
                      ),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          labels[i],
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: on ? FontWeight.w800 : FontWeight.w600,
                            color: on ? Colors.white : AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          height: 2,
                          width: on ? 22 : 0,
                          color: AppColors.cyan,
                        ),
                      ],
                    ),
                  ),
          );
        },
      ),
    );
  }
}

/// Row header: accent bar + title (+ optional bilingual / trailing text).
class TvSectionTitle extends StatelessWidget {
  const TvSectionTitle(
    this.title, {
    super.key,
    this.trailing,
    this.arabicTitle,
    this.accent,
    this.onTap,
    this.trailingBesideTitle = false,
  });
  final String title;
  final String? trailing;
  final String? arabicTitle;
  final Color? accent;
  final VoidCallback? onTap;

  /// [trailing] directly after the title instead of at the far end, without
  /// the arrow (package headings, client 9 Nov).
  final bool trailingBesideTitle;

  @override
  Widget build(BuildContext context) {
    final bar = accent ?? AppColors.cyan;
    final ar = (arabicTitle ?? '').trim();
    final besideTitle = trailingBesideTitle ? trailing : null;
    final atEnd = trailingBesideTitle ? null : trailing;
    final row = Row(
      children: [
        Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            color: bar,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TvUi.section,
                ),
              ),
              if (ar.isNotEmpty) ...[
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    ar,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TvUi.titleArabic.copyWith(fontSize: 13),
                    textDirection: TextDirection.rtl,
                  ),
                ),
              ],
              if (besideTitle != null) ...[
                const SizedBox(width: 10),
                Text(
                  besideTitle,
                  style: TextStyle(
                    color: bar,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (atEnd != null) ...[
          const SizedBox(width: 12),
          Text(
            atEnd,
            style: TextStyle(
              color: bar,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          // View All / Explore All: real iOS forward icon, not ">".
          if (onTap != null) ...[
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 12,
              color: bar,
              textDirection: Directionality.of(context),
            ),
          ],
        ],
      ],
    );
    if (onTap == null) return row;
    return FocusableActionDetector(
      onShowFocusHighlight: (_) {},
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            onTap!();
            return null;
          },
        ),
        // "View All" is the only stop on its line: Left/Right stay here
        // (client 21 Oct TV #5: Left jumped up to the row above).
        DirectionalFocusIntent: CallbackAction<DirectionalFocusIntent>(
          onInvoke: (intent) {
            if (intent.direction == TraversalDirection.up ||
                intent.direction == TraversalDirection.down) {
              primaryFocus?.focusInDirection(intent.direction);
            }
            return null;
          },
        ),
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: focused
                      ? Border.all(color: bar.withValues(alpha: 0.85), width: 2)
                      : null,
                ),
                child: row,
              ),
            ),
          );
        },
      ),
    );
  }
}
