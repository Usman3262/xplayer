import 'package:design_system/design_system.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/library_controller.dart';
import '../core/session_controller.dart';

/// Thumbs up / down + Remind Me (favorites API when logged in).
class RateRemindBar extends ConsumerWidget {
  const RateRemindBar({
    super.key,
    required this.id,
    this.item,
    this.showRemind = true,
    this.compact = false,
  });

  final String id;
  final MediaItem? item;
  final bool showRemind;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lib = ref.watch(libraryProvider);
    final copy = AppCopy.ofLanguage(
      ref.watch(sessionProvider.select((s) => s.language)),
    );
    // The rating just tapped wins over the server's favourites list, which
    // only refreshes after the server answers (17 Oct phone test: Dislike
    // left "Liked" lit, so the change looked like it did nothing).
    final rated = lib.ratings[id];
    final liked =
        rated != null ? rated == 1 : lib.liked.any((e) => e.id == id);
    final disliked = rated == -1;
    final reminded = lib.hasReminder(id);

    return Row(
      children: [
        _Chip(
          icon: liked ? Icons.thumb_up_rounded : Icons.thumb_up_outlined,
          label: compact ? null : (liked ? copy.likedLabel : copy.like),
          active: liked,
          onTap: () async {
            final nextLiked = !liked;
            await ref.read(libraryProvider.notifier).setRating(
                  id,
                  liked ? 0 : 1,
                  item: item,
                );
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(nextLiked ? copy.likedLabel : copy.like),
              ),
            );
          },
        ),
        const SizedBox(width: 8),
        _Chip(
          icon: disliked
              ? Icons.thumb_down_rounded
              : Icons.thumb_down_outlined,
          label: compact ? null : copy.dislike,
          active: disliked,
          magenta: true,
          onTap: () async {
            // Second tap clears the dislike, like Like does.
            await ref.read(libraryProvider.notifier).setRating(
                  id,
                  disliked ? 0 : -1,
                  item: item,
                );
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(copy.dislike)),
            );
          },
        ),
        if (showRemind) ...[
          const SizedBox(width: 8),
          _Chip(
            icon: reminded
                ? Icons.notifications_active_rounded
                : Icons.notifications_none_rounded,
            label: compact ? null : (reminded ? copy.reminded : copy.remindMe),
            active: reminded,
            onTap: () =>
                ref.read(libraryProvider.notifier).toggleReminder(id, item: item),
          ),
        ],
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.onTap,
    this.label,
    this.active = false,
    this.magenta = false,
  });

  final IconData icon;
  final String? label;
  final bool active;
  final bool magenta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = magenta
        ? (active ? AppColors.magenta : AppColors.textSecondary)
        : (active ? AppColors.cyan : AppColors.textSecondary);
    return Material(
      color: AppColors.surfaceElevated,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: label == null ? 10 : 12,
            vertical: 8,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: color),
              if (label != null) ...[
                const SizedBox(width: 6),
                Text(
                  label!,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
