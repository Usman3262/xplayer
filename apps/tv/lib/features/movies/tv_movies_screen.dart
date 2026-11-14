import 'package:domain/domain.dart';
import 'package:flutter/material.dart';

import '../../widgets/tv_catalog_browse.dart';

/// Figma: the app TV Movies Browse. Banner, category chips, one row per
/// category with View All.
class TvMoviesScreen extends StatelessWidget {
  const TvMoviesScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const TvCatalogBrowse(kind: MediaKind.movie);
}
