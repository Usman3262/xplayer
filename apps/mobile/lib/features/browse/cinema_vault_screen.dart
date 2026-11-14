import 'package:data/data.dart';
import 'package:design_system/design_system.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/media_nav.dart';
import '../../core/providers.dart';
import '../../core/session_controller.dart';

/// Movie / series packages that hold 4K copies ("MOVIES 4K", "UHD …").
final _uhdCategory = RegExp(r'(4K|UHD|2160)', caseSensitive: false);

/// True for a title in [cinemaVaultProvider]: a 4K copy, never SD / HD.
bool isVaultTitle(MediaItem m, {required bool inUhdPackage}) =>
    (m.kind == MediaKind.movie || m.kind == MediaKind.series) &&
    (inUhdPackage || isUhdItem(m));

/// APP Cinema Vault (client 23 Oct round 3 #17): only movies and series
/// that are actually in 4K, Arabic or international. Read from the 4K
/// packages of the catalog, plus titles the provider labels 4K / UHD; it
/// was a fixed "84 titles" button that opened every movie.
final cinemaVaultProvider = FutureProvider.autoDispose<List<MediaItem>>((ref) async {
  ref.keepAlive();
  final repo = ref.watch(catalogRepositoryProvider);
  final out = <MediaItem>[];
  final seen = <String>{};
  for (final kind in [MediaKind.movie, MediaKind.series]) {
    final cats = await repo.getCategories(kind);
    // A handful of 4K packages per kind; each read in pages of 100.
    for (final c in cats.where((c) => _uhdCategory.hasMatch(c.name)).take(8)) {
      String? cursor;
      for (var page = 0; page < 6; page++) {
        final p = await repo.browse(kind: kind, categoryId: c.id, cursor: cursor, limit: 100);
        for (final m in p.items) {
          if (isVaultTitle(m, inUhdPackage: true) && seen.add('${m.kind.name}:${m.id}')) out.add(m);
        }
        if (!p.hasMore || p.nextCursor == null) break;
        cursor = p.nextCursor;
      }
    }
  }
  return out;
});

class CinemaVaultScreen extends ConsumerWidget {
  const CinemaVaultScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = AppCopy.ofLanguage(ref.watch(sessionProvider.select((s) => s.language)));
    final vault = ref.watch(cinemaVaultProvider);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text(copy.cinemaVaultTitle, style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: vault.when(
        loading: () => Center(child: AppLoader.inline(size: 32)),
        error: (_, _) => Center(
          child: TextButton(
            onPressed: () => ref.invalidate(cinemaVaultProvider),
            child: Text(copy.retry),
          ),
        ),
        data: (items) => items.isEmpty
            ? Center(
                child: Text(copy.cinemaVaultEmpty,
                    textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)),
              )
            : GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 12,
                  childAspectRatio: PosterCard.standardWidth / PosterCard.railHeightFor(PosterCard.standardWidth),
                ),
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final item = items[i];
                  return LayoutBuilder(
                    builder: (context, c) => PosterCard(
                      title: item.displayTitle,
                      rating: item.posterRating,
                      badges: const ['4K'],
                      imageUrl: item.posterUrl,
                      seed: item.posterSeed ?? i,
                      width: c.maxWidth,
                      onTap: () => openMediaBrowse(context, item),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
