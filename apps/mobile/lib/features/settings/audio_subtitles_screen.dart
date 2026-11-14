import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session_controller.dart';
import '../../widgets/main_app_bar.dart';

class AudioSubtitlesScreen extends ConsumerWidget {
  const AudioSubtitlesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final copy = AppCopy.ofLanguage(session.language);
    final options = const ['Dolby Atmos', 'Stereo', 'Arabic (Master)', 'English'];
    return Scaffold(
      appBar: const MainAppBar(showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            copy.audioSubtitles,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22),
          ),
          const SizedBox(height: 12),
          ...options.map(
            (o) => RadioListTile<String>(
              value: o,
              groupValue: session.audioPref,
              activeColor: AppColors.cyan,
              title: Text(copy.audioPrefLabel(o)),
              onChanged: (v) {
                if (v != null) {
                  ref.read(sessionProvider.notifier).setAudioPref(v);
                }
              },
            ),
          ),
          Divider(color: AppColors.border),
          ListTile(
            title: Text(copy.preferredSubtitles),
            subtitle: Text(copy.preferredSubtitlesList),
            trailing: const TechBadge('AR / EN', compact: true),
          ),
        ],
      ),
    );
  }
}
