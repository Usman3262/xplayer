import 'package:domain/domain.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Open catalog / library items with the right TV route.
///
/// Task #143 #12: movies/series open details first unless [preferPlay].
/// Live / sports / explicit Play go to the player.
void openTvMedia(
  BuildContext context,
  MediaItem item, {
  bool preferPlay = false,
}) {
  // A series-level item (no episode id) cannot be played: the provider
  // answers HTTP 405. Open its details, where Play picks an episode.
  final seriesOnly = item.kind == MediaKind.series &&
      (item.seriesId == null ||
          item.seriesId!.isEmpty ||
          item.seriesId == item.id);

  if (preferPlay && !seriesOnly) {
    context.push(item.playbackRoute(), extra: item);
    return;
  }

  if (item.kind == MediaKind.series || item.kind == MediaKind.movie) {
    final sid = item.seriesId;
    if (item.kind == MediaKind.series && sid != null && sid.isNotEmpty) {
      context.push('/details/$sid', extra: item);
    } else {
      context.push('/details/${item.id}', extra: item);
    }
    return;
  }

  context.push(item.playbackRoute(), extra: item);
}
