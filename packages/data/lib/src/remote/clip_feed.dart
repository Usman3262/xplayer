import 'dart:math';

import 'package:domain/domain.dart';

/// One card in the vertical Clips Reels feed (built from catalog, not a clips API).
class ClipFeedItem {
  const ClipFeedItem({
    required this.catalogId,
    required this.title,
    required this.contentType,
    this.posterUrl,
    this.containerExtension,
  });

  /// VOD streamId, seriesId, or live streamId.
  final String catalogId;
  final String title;
  final String? posterUrl;

  /// `vod` | `series` | `live`
  final String contentType;
  final String? containerExtension;

  bool get isLive => contentType == 'live';
  bool get isSeries => contentType == 'series';
  bool get isVod => contentType == 'vod';

  /// Customer-facing title (never the placeholder literal "Title").
  String get displayTitle {
    final cleaned = cleanDisplayName(title).trim();
    if (cleaned.isNotEmpty && cleaned.toLowerCase() != 'title') {
      return cleaned;
    }
    return catalogId.isNotEmpty ? catalogId : 'Untitled';
  }
}

/// True when container is easier than progressive 4K MKV for short previews.
bool isLightClipContainer(String? containerExtension, {bool isLive = false}) {
  if (isLive) return true;
  final e = (containerExtension ?? '').toLowerCase().trim();
  return e == 'mp4' ||
      e == 'm3u8' ||
      e == 'ts' ||
      e == 'mp3' ||
      e == 'webm';
}

/// Mix VOD + series + live in a balanced random interleave (not live-only).
List<ClipFeedItem> buildClipFeed({
  required List<MediaItem> movies,
  required List<MediaItem> series,
  required List<LiveChannel> live,
  int limit = 10,
  Random? random,
}) {
  final rng = random ?? Random();
  final vod = [
    for (final m in movies)
      ClipFeedItem(
        catalogId: m.id,
        title: m.displayTitle,
        posterUrl: m.posterUrl ?? m.backdropUrl,
        contentType: 'vod',
        containerExtension: m.containerExtension,
      ),
  ]..shuffle(rng);
  final seriesItems = [
    for (final s in series)
      ClipFeedItem(
        catalogId: s.id,
        title: s.displayTitle,
        posterUrl: s.posterUrl ?? s.backdropUrl,
        contentType: 'series',
        containerExtension: s.containerExtension,
      ),
  ]..shuffle(rng);
  final liveItems = [
    for (final c in live)
      ClipFeedItem(
        catalogId: c.id,
        title: c.name,
        posterUrl: c.imageUrl,
        contentType: 'live',
      ),
  ]..shuffle(rng);

  final out = <ClipFeedItem>[];
  var vi = 0;
  var si = 0;
  var li = 0;
  // Round-robin across categories so the feed is a mixture, not all live.
  while (out.length < limit) {
    final kinds = ['vod', 'series', 'live']..shuffle(rng);
    var added = false;
    for (final kind in kinds) {
      if (out.length >= limit) break;
      if (kind == 'vod' && vi < vod.length) {
        out.add(vod[vi++]);
        added = true;
      } else if (kind == 'series' && si < seriesItems.length) {
        out.add(seriesItems[si++]);
        added = true;
      } else if (kind == 'live' && li < liveItems.length) {
        out.add(liveItems[li++]);
        added = true;
      }
    }
    if (!added) break;
  }
  return out;
}

/// Mid-window seek: skip ~15% head/tail; clip length 10–15s.
({Duration start, Duration end, int clipSec}) pickMidClipWindow(
  Duration total, {
  Random? random,
}) {
  final rng = random ?? Random();
  final clipSec = 10 + rng.nextInt(6); // 10..15
  final totalSec = total.inSeconds;
  if (totalSec <= 0) {
    return (
      start: Duration.zero,
      end: Duration(seconds: clipSec),
      clipSec: clipSec,
    );
  }
  if (totalSec < 45) {
    final start = Duration(seconds: (totalSec * 0.2).round());
    final endSec = (start.inSeconds + clipSec).clamp(0, totalSec);
    return (start: start, end: Duration(seconds: endSec), clipSec: clipSec);
  }
  final usable = totalSec * 0.70; // middle 70%
  final head = totalSec * 0.15;
  final offset = rng.nextDouble() * (usable - clipSec).clamp(0, usable);
  final startSec = (head + offset).round().clamp(0, totalSec - 1);
  final endSec = (startSec + clipSec).clamp(0, totalSec);
  return (
    start: Duration(seconds: startSec),
    end: Duration(seconds: endSec),
    clipSec: clipSec,
  );
}

/// Progressive `.mkv` / raw files often cannot mid-seek quickly over HTTP.
bool isProgressiveHardSeekUrl(String playUrl) {
  final u = playUrl.toLowerCase();
  if (u.contains('.m3u8') || u.contains('format=m3u8')) return false;
  return u.contains('.mkv') || u.contains('/movie/');
}

/// Prefer a light intro-skip window when deep mid-seek is unreliable.
({Duration start, Duration end, int clipSec}) pickClipWindowForUrl(
  String playUrl,
  Duration total, {
  Random? random,
}) {
  final rng = random ?? Random();
  final clipSec = 10 + rng.nextInt(6);
  if (!isProgressiveHardSeekUrl(playUrl) && total.inSeconds > 90) {
    return pickMidClipWindow(total, random: rng);
  }
  // Progressive: skip ~30–90s intro when duration unknown/long, else mid if known.
  if (total.inSeconds > 180) {
    final startSec = 30 + rng.nextInt(61);
    return (
      start: Duration(seconds: startSec),
      end: Duration(seconds: startSec + clipSec),
      clipSec: clipSec,
    );
  }
  if (total.inSeconds > 45) {
    return pickMidClipWindow(total, random: rng);
  }
  return (
    start: Duration.zero,
    end: Duration(seconds: clipSec),
    clipSec: clipSec,
  );
}
