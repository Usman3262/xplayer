import 'package:design_system/design_system.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session_controller.dart';
import '../../widgets/category_channel_trails.dart';

class LiveTvScreen extends ConsumerWidget {
  const LiveTvScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(sessionProvider.select((s) => s.language));
    final copy = AppCopy.ofLanguage(language);
    return CategoryChannelTrailsScreen(
      kind: MediaKind.live,
      eyebrow: copy.liveTv,
      searchHint: copy.searchLive,
      sportsOnly: false,
    );
  }
}
