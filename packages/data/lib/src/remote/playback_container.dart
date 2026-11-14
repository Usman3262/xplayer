import 'package:domain/domain.dart';
import 'package:flutter/foundation.dart';

/// Resolves the container for `POST /playback/start`.
///
/// The backend defaults to `.mp4` when [containerExtension] is omitted. This
/// catalog is mostly `.mkv`, so a missing field produces a dead playUrl.
/// Prefer a known/cached value; for non-live content fall back to `mkv`.
Future<String?> resolvePlaybackContainer({
  required CatalogRepository catalog,
  required String contentType,
  required String streamId,
  String? known,
  String? seriesId,
  Future<Episode?> Function(String seriesId, String episodeId)? findEpisode,
}) async {
  var ext = _nonEmpty(known) ?? catalog.knownContainerExtension(streamId);
  if (ext == null &&
      contentType == 'series' &&
      findEpisode != null) {
    final parent =
        _nonEmpty(seriesId) ?? catalog.knownSeriesIdForEpisode(streamId);
    if (parent != null) {
      final ep = await findEpisode(parent, streamId);
      ext = _nonEmpty(ep?.containerExtension);
    }
  }
  if (contentType == 'live') return null;
  if (ext != null) return ext;
  debugPrint(
    '[Playback] WARNING: no containerExtension for streamId=$streamId '
    'contentType=$contentType — defaulting to mkv',
  );
  return 'mkv';
}

String? _nonEmpty(String? value) {
  if (value == null) return null;
  final t = value.trim();
  return t.isEmpty ? null : t;
}
