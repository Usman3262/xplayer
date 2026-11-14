import '../entities/catalog_page.dart';
import '../entities/episode.dart';
import '../entities/home_feed.dart';
import '../entities/live_channel.dart';
import '../entities/media_item.dart';
import '../entities/sports_match.dart';

abstract class CatalogRepository {
  Future<HomeFeed> getHomeFeed();
  Future<List<MediaItem>> getMovies();
  Future<List<MediaItem>> getSeries();
  Future<List<LiveChannel>> getLiveChannels();
  Future<List<SportsMatch>> getSportsMatches();

  /// Sports tab: 10 channels per page. Walks sports live categories.
  Future<CatalogPage<SportsMatch>> browseSports({
    String? cursor,
    int limit = 10,
  });

  /// Sports channels the package includes that match [query].
  Future<List<SportsMatch>> searchSports(String query);
  Future<List<MediaItem>> getMyList();

  /// Home / global search across catalog. Pass [kind] to limit to one section.
  /// First page only — prefer [searchPage] when the UI can load more.
  Future<List<MediaItem>> search(String query, {MediaKind? kind});

  /// Cursor-paged search (`meta.nextCursor`).
  Future<CatalogPage<MediaItem>> searchPage(
    String query, {
    MediaKind? kind,
    String? cursor,
    int limit = 40,
    /// Only titles in this package (provider category id).
    String? categoryId,
  });

  Future<MediaItem?> getById(String id, {MediaKind? kind});

  /// Container from a prior catalog/series-detail load, if any.
  String? knownContainerExtension(String streamId);

  /// Parent series id for an episode stream, if previously indexed.
  String? knownSeriesIdForEpisode(String episodeId);

  /// Category chips for Movies / Series / Live tab browsers.
  Future<List<CatalogCategory>> getCategories(MediaKind kind);

  /// Tab browsers: 10 items per page with cursor pagination.
  Future<CatalogPage<MediaItem>> browse({
    required MediaKind kind,
    String? categoryId,
    String? cursor,
    int limit = 10,
  });

  Future<List<String>> getGenres();
  Future<List<MediaItem>> getByGenre(String genre);
  Future<List<Episode>> getEpisodes(String seriesId, {int season = 1});

  /// Number of seasons available for a series (mock: typically 2).
  Future<int> getSeasonCount(String seriesId);

  /// The provider's own season numbers that have episodes, ascending
  /// (e.g. `[1, 3]` or `[0, 1]`). Seasons are not always 1..N, so UI tabs and
  /// episode playlists must use these numbers, not a 1..count loop.
  Future<List<int>> getSeasonNumbers(String seriesId);

  /// Same-genre / similar titles for “More like this”.
  Future<List<MediaItem>> getRelated(String id);

  Future<List<MediaItem>> getTrending();
  /// Newest movies first (provider date added).
  Future<List<MediaItem>> getNewReleases();

  /// Newest series first (provider last update).
  Future<List<MediaItem>> getNewSeries();

  /// Upcoming titles rail (mock flags / badges).
  Future<List<MediaItem>> getComingSoon();
}
