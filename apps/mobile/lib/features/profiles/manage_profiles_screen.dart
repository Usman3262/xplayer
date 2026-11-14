import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/session_controller.dart';
import '../../widgets/main_app_bar.dart';

class ManageProfilesScreen extends ConsumerStatefulWidget {
  const ManageProfilesScreen({super.key});

  @override
  ConsumerState<ManageProfilesScreen> createState() =>
      _ManageProfilesScreenState();
}

class _ManageProfilesScreenState extends ConsumerState<ManageProfilesScreen> {
  final _name = TextEditingController();
  bool _kids = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final copy = AppCopy.ofLanguage(session.language);
    return Scaffold(
      appBar: const MainAppBar(showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            copy.manageProfiles,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22),
          ),
          const SizedBox(height: 6),
          Text(
            copy.profilesOfLimitActive(session.profiles.length),
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          ...session.profiles.map(
            (p) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              clipBehavior: Clip.antiAlias,
              // Own Material: the tap ripple shows over the tile colour
              // (Flutter warned 32 times in the 12 Nov simulator log).
              child: Material(
                color: Colors.transparent,
                child: ListTile(
                  leading: ProfileAvatar(
                    initials: p.initials,
                    token: p.avatar,
                    size: 40,
                  ),
                  title: Text(p.name),
                  subtitle: Text(
                    [
                      if (p.isKids) copy.kids,
                      if (p.hasPin) copy.pinProtected,
                      if (p.isActive) copy.profileActive,
                    ].join(' • '),
                  ),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => context.push('/profiles/edit/${p.id}'),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            copy.addProfile,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _name,
            style: TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: copy.profileName,
              filled: true,
              fillColor: AppColors.surfaceElevated,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          SwitchListTile(
            title: Text(copy.kidsProfile),
            value: _kids,
            activeThumbColor: AppColors.cyan,
            onChanged: (v) => setState(() => _kids = v),
          ),
          NeonPulse(
            child: PrimaryButton(
              label: copy.createProfile,
              icon: Icons.add_rounded,
              onPressed: () async {
                if (_name.text.trim().isEmpty) return;
                try {
                  await ref
                      .read(sessionProvider.notifier)
                      .addProfile(_name.text, kids: _kids);
                  _name.clear();
                  setState(() => _kids = false);
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(AppAlerts.clean(e))),
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
