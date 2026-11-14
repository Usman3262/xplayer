/// Cursor-paged catalog slice (backend `meta.nextCursor`).
class CatalogPage<T> {
  const CatalogPage({
    required this.items,
    this.nextCursor,
    this.total,
  });

  final List<T> items;
  final String? nextCursor;
  final int? total;

  bool get hasMore => nextCursor != null && nextCursor!.isNotEmpty;
}

class CatalogCategory {
  const CatalogCategory({required this.id, required this.name, this.isSports});

  final String id;
  final String name;

  /// Backend sports flag for live categories; null = not provided.
  final bool? isSports;
}
