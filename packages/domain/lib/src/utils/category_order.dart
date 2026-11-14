import '../entities/catalog_page.dart';

/// Applies a saved package order (category ids): saved packages first, in
/// that order; packages the order does not know (new in the catalog) follow
/// in provider order; ids no longer in the catalog are ignored. So a catalog
/// update never resets the user's order.
List<CatalogCategory> applyCategoryOrder(
  List<CatalogCategory> categories,
  List<String> orderIds,
) {
  if (orderIds.isEmpty) return categories;
  final rank = <String, int>{
    for (var i = 0; i < orderIds.length; i++) orderIds[i]: i,
  };
  final known = [
    for (final c in categories)
      if (rank.containsKey(c.id)) c,
  ]..sort((a, b) => rank[a.id]!.compareTo(rank[b.id]!));
  return [
    ...known,
    for (final c in categories)
      if (!rank.containsKey(c.id)) c,
  ];
}
