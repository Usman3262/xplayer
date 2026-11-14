import 'package:design_system/design_system.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session_controller.dart';
import '../../widgets/catalog_browse_screen.dart';

class SeriesScreen extends ConsumerWidget {
  const SeriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(sessionProvider.select((s) => s.language));
    final copy = AppCopy.ofLanguage(language);
    return CatalogBrowseScreen(
      kind: MediaKind.series,
      eyebrow: copy.series,
      searchHint: copy.searchSeries,
    );
  }
}
