import 'api_client.dart';
import 'api_exception.dart';
import 'media_models.dart';

class CatalogApi {
  CatalogApi(this._client);

  final ApiClient _client;

  Future<List<CatalogCategoryDto>> liveCategories() async {
    final data = await _client.get('/catalog/live/categories', auth: true);
    return parseCategoriesAsync(data);
  }

  Future<PageResult<CatalogStreamDto>> liveStreams({
    String? categoryId,
    int limit = 10,
    String? cursor,
  }) {
    return _pagedStreams(
      '/catalog/live/streams',
      categoryId: categoryId,
      limit: limit,
      cursor: cursor,
    );
  }

  Future<List<CatalogCategoryDto>> vodCategories() async {
    final data = await _client.get('/catalog/vod/categories', auth: true);
    return parseCategoriesAsync(data);
  }

  Future<PageResult<CatalogStreamDto>> vodStreams({
    String? categoryId,
    int limit = 10,
    String? cursor,
    String? sort,
  }) {
    return _pagedStreams(
      '/catalog/vod/streams',
      categoryId: categoryId,
      limit: limit,
      cursor: cursor,
      sort: sort,
    );
  }

  Future<List<CatalogCategoryDto>> seriesCategories() async {
    final data = await _client.get('/catalog/series/categories', auth: true);
    return parseCategoriesAsync(data);
  }

  Future<PageResult<CatalogStreamDto>> seriesList({
    String? categoryId,
    int limit = 10,
    String? cursor,
    String? sort,
  }) {
    return _pagedStreams(
      '/catalog/series',
      categoryId: categoryId,
      limit: limit,
      cursor: cursor,
      sort: sort,
    );
  }

  Future<SeriesDetailDto> seriesDetail(String seriesId) async {
    final data = await _client.get('/catalog/series/$seriesId', auth: true);
    if (data == null) throw ApiException('Empty series detail');
    return parseSeriesDetailAsync(data);
  }

  Future<PageResult<CatalogStreamDto>> search({
    required String q,
    String kind = 'all',
    int limit = 10,
    String? cursor,
    String? categoryId,
  }) async {
    final query = <String, String>{
      'q': q,
      'kind': kind,
      if (categoryId != null && categoryId.isNotEmpty) 'categoryId': categoryId,
      'limit': '$limit',
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
    };
    final env = await _client.getEnvelope(
      '/catalog/search',
      auth: true,
      query: query,
    );
    return PageResult(
      items: await parseStreamsAsync(env.data),
      nextCursor: env.nextCursor,
      total: env.total,
    );
  }

  Future<PageResult<CatalogStreamDto>> _pagedStreams(
    String path, {
    String? categoryId,
    int limit = 10,
    String? cursor,
    String? sort,
  }) async {
    final query = <String, String>{
      'limit': '${limit.clamp(1, 100)}',
      if (sort != null) 'sort': sort,
      if (categoryId != null && categoryId.isNotEmpty) 'categoryId': categoryId,
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
    };
    final env = await _client.getEnvelope(path, auth: true, query: query);
    return PageResult(
      items: await parseStreamsAsync(env.data),
      nextCursor: env.nextCursor,
      total: env.total,
    );
  }
}
