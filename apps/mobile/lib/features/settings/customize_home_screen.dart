import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session_controller.dart';
import '../../widgets/main_app_bar.dart';

class CustomizeHomeScreen extends ConsumerWidget {
  const CustomizeHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final copy = AppCopy.ofLanguage(session.language);
    final sections = session.homeSections;
    return Scaffold(
      appBar: const MainAppBar(showBack: true),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              copy.customizeHome,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              copy.customizeHomeHint,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: sections.length,
              onReorder: (oldIndex, newIndex) {
                ref
                    .read(sessionProvider.notifier)
                    .reorderHomeSections(oldIndex, newIndex);
              },
              itemBuilder: (context, i) {
                final title = sections[i];
                return Container(
                  key: ValueKey(title),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Material(
                    color: Colors.transparent,
                    child: ListTile(
                      leading: Container(
                        width: 4,
                        height: 28,
                        decoration: BoxDecoration(
                          color: AppColors.cyan,
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.cyan.withValues(alpha: 0.5),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                      title: Text(
                        copy.homeSectionLabel(title),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(copy.priorityN(i + 1)),
                      trailing: const Icon(Icons.drag_handle_rounded),
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: NeonPulse(
              child: PrimaryButton(
                label: copy.saveHomeLayout,
                icon: Icons.check_rounded,
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
