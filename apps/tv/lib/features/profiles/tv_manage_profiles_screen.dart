import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/tv_locale.dart';
import '../../core/tv_session.dart';
import '../../widgets/focus_tile.dart';
import '../settings/tv_security_scaffold.dart';

/// TV port of mobile [ManageProfilesScreen] — list + navigate to edit.
class TvManageProfilesScreen extends ConsumerWidget {
  const TvManageProfilesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(tvLanguageProvider);
    final copy = AppCopy.ofLanguage(language);
    final session = ref.watch(tvSessionProvider);
    final profiles = session.profiles;

    return TvSecurityScaffold(
      title: copy.manageProfiles,
      subtitle: copy.profilesOfLimitActive(profiles.length),
      child: ListView.separated(
        itemCount: profiles.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final p = profiles[i];
          final bits = <String>[
            if (p.isKids) copy.kids,
            if (p.hasPin) copy.pinProtected,
            if (session.activeProfileId == p.id) copy.profileActive,
          ];
          return FocusTile(
            autofocus: i == 0,
            borderRadius: 14,
            focusScale: 1.0,
            onTap: () => context.push('/profiles/edit/${p.id}'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: p.color.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: p.color),
                    ),
                    child: ProfileAvatarFace(initials: p.initials, token: p.avatar, color: p.color, fontSize: 16, radius: 12),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        if (bits.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            bits.join(' • '),
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(Icons.edit_outlined, color: AppColors.cyan),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
