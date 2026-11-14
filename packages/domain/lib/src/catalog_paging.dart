/// Shared catalog page size for rails, grids, lists, and API chunks.
abstract final class CatalogPaging {
  /// Channels / titles fetched per package rail or grid page.
  static const pageSize = 10;

  /// How many category/package rows to reveal per scroll page.
  /// Keeps Live/VOD from requesting every package at once (HTTP 429).
  static const categoriesPageSize = 15;
}
