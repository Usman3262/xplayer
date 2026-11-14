import 'package:design_system/design_system.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/library_controller.dart';
import '../core/tv_locale.dart';
import 'focus_tile.dart';

/// TV thumbs + Remind Me.
class TvRateRemindBar extends ConsumerWidget {
  const TvRateRemindBar({
    super.key,
    required this.id,
    this.item,
    this.showRemind = true,
  });

  final String id;
  final MediaItem? item;
  final bool showRemind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lib = ref.watch(libraryProvider);
    final copy = AppCopy.ofLanguage(ref.watch(tvLanguageProvider));
    final rating = lib.ratingFor(id);
    final reminded = lib.hasReminder(id);

    return Row(
      children: [
        FocusTile(
          borderRadius: 999,
          onTap: () => ref
              .read(libraryProvider.notifier)
              .setRating(id, 1, item: item),
          child: _pill(
            rating == 1 ? copy.likedLabel : copy.like,
            active: rating == 1,
          ),
        ),
        const SizedBox(width: 10),
        FocusTile(
          borderRadius: 999,
          onTap: () => ref
              .read(libraryProvider.notifier)
              .setRating(id, -1, item: item),
          child: _pill(
            copy.dislike,
            active: rating == -1,
            magenta: true,
          ),
        ),
        if (showRemind) ...[
          const SizedBox(width: 10),
          FocusTile(
            borderRadius: 999,
            onTap: () =>
                ref.read(libraryProvider.notifier).toggleReminder(id, item: item),
            child: _pill(
              reminded ? copy.reminded : copy.remindMe,
              active: reminded,
            ),
          ),
        ],
      ],
    );
  }

  Widget _pill(String label, {bool active = false, bool magenta = false}) {
    final accent = magenta ? AppColors.magenta : AppColors.cyan;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: active ? accent.withValues(alpha: 0.2) : AppColors.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: active ? accent : AppColors.border),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
    );
  }
}
