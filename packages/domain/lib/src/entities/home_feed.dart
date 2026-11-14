import 'live_channel.dart';
import 'media_item.dart';
import 'sports_match.dart';

class HomeFeed {
  const HomeFeed({
    required this.hero,
    required this.matches,
    required this.continueWatching,
    required this.top10,
    required this.arabicOriginals,
    required this.liveChannels,
  });

  final MediaItem hero;
  final List<SportsMatch> matches;
  final List<MediaItem> continueWatching;
  final List<MediaItem> top10;
  final List<MediaItem> arabicOriginals;
  final List<LiveChannel> liveChannels;
}
