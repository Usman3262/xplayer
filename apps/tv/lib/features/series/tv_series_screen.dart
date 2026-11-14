import 'package:domain/domain.dart';
import 'package:flutter/material.dart';

import '../../widgets/tv_catalog_browse.dart';

/// Figma: the app TV Series Browse. Banner, category chips, one row per
/// category with View All.
class TvSeriesScreen extends StatelessWidget {
  const TvSeriesScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const TvCatalogBrowse(kind: MediaKind.series);
}
