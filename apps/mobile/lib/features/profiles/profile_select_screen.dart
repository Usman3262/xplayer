import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/session_models.dart';
import '../../core/session_controller.dart';
import '../../widgets/action_feedback.dart';
import 'kids_pin.dart';

class ProfileSelectScreen extends ConsumerStatefulWidget {
  const ProfileSelectScreen({super.key});

  @override
  ConsumerState<ProfileSelectScreen> createState() =>
      _ProfileSelectScreenState();
}

class _ProfileSelectScreenState extends ConsumerState<ProfileSelectScreen> {
  String? _error;

  Future<void> _openProfile(ViewingProfile profile) async {
    setState(() => _error = null);
    final ok = await openProfileWithKidsPin(context, ref, profile);
    if (!ok || !mounted) return;
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final copy = AppCopy.ofLanguage(session.language);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Align(
                alignment: AlignmentDirectional.centerStart,
                child: AppLogo(height: 76, alignToStart: true),
              ),
              const SizedBox(height: 24),
              Text(
                copy.whosWatching,
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 26),
              ),
              const SizedBox(height: 6),
              Text(
                copy.chooseProfile,
                style: TextStyle(color: AppColors.textSecondary),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: TextStyle(color: AppColors.danger)),
              ],
              const SizedBox(height: 28),
              Expanded(
                child: GridView.builder(
                  itemCount: session.profiles.length + 1,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: 0.95,
                  ),
                  itemBuilder: (context, i) {
                    if (i == session.profiles.length) {
                      return NeonTap(
                        onTap: () => context.push('/profiles/manage'),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: AppColors.border),
                            color: AppColors.surface,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_rounded,
                                  color: AppColors.cyan, size: 36),
                              const SizedBox(height: 8),
                              // Client 9 Nov: "Add Profile", not "Manage".
                              Text(copy.addProfile),
                            ],
                          ),
                        ),
                      );
                    }
                    final p = session.profiles[i];
                    return NeonTap(
                      color: p.isKids ? AppColors.gold : AppColors.cyan,
                      onTap: () => _openProfile(p),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: p.isActive
                                ? AppColors.cyan
                                : AppColors.border,
                          ),
                          gradient: LinearGradient(
                            colors: [
                              AppColors.surfaceElevated,
                              p.isKids
                                  ? const Color(0xFF2A2208)
                                  : const Color(0xFF0C1A22),
                            ],
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ProfileAvatar(
                              initials: p.initials,
                              token: p.avatar,
                              size: 68,
                            ),
                            if (!p.isKids) ...[
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.gold,
                                  borderRadius: BorderRadius.circular(4),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.gold
                                          .withValues(alpha: 0.4),
                                      blurRadius: 6,
                                    ),
                                  ],
                                ),
                                child: const Text(
                                  'VIP',
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 10),
                            Text(
                              p.name,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            if (p.hasPin)
                              Padding(
                                padding: EdgeInsets.only(top: 4),
                                child: Icon(Icons.lock_rounded,
                                    size: 14, color: AppColors.textSecondary),
                              ),
                            if (p.isKids)
                              const Padding(
                                padding: EdgeInsets.only(top: 6),
                                child: TechBadge('KIDS',
                                    tone: BadgeTone.gold, compact: true),
                              ),
                          ],
                        ),
                      ),
                    )
                        .animate()
                        .fadeIn(delay: (80 * i).ms)
                        .scale(begin: const Offset(0.92, 0.92));
                  },
                ),
              ),
              TextButton(
                onPressed: () async {
                  final ok = await ActionFeedback.confirm(
                    context,
                    title: copy.signOutConfirmTitle,
                    message: copy.signOutConfirmMessage,
                    confirmLabel: copy.signOutShort,
                    cancelLabel: copy.cancel,
                    destructive: true,
                  );
                  if (!ok || !context.mounted) return;
                  await ref.read(sessionProvider.notifier).signOut();
                  if (context.mounted) context.go('/connect');
                },
                child: Text(
                  copy.signOutShort,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
