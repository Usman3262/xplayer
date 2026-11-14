import 'package:domain/domain.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Shared mobile navigation into details / player.
///
/// Task #143 #12: movies and series open details first (Play Now from there).
/// Live / sports still open the player (no VOD-style details hub).
void openMediaBrowse(BuildContext context, MediaItem item) {
  switch (item.kind) {
    case MediaKind.movie:
      context.push('/movie/${item.id}', extra: item);
    case MediaKind.series:
      final seriesKey = (item.seriesId != null && item.seriesId!.isNotEmpty)
          ? item.seriesId!
          : item.id;
      context.push('/series/$seriesKey', extra: item);
    case MediaKind.live:
    case MediaKind.sports:
      context.push(item.playbackRoute());
  }
}

/// Open the player for [item] (resume / Watch Now / live tap).
void openMediaPlayback(BuildContext context, MediaItem item) {
  context.push(item.playbackRoute());
}
