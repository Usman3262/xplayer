import 'package:domain/domain.dart';

import 'provider_models.dart';

/// Provider models → the existing domain entities the screens already use
/// (D5/D17: new data plugs into the current screens, no redesign).
/// Stream URLs are left empty on purpose: they are built at play time by
/// `ProviderAdapter.resolveStream`, so credentials never sit in the catalog.

CatalogCategory providerCategoryToDomain(ProviderCategory c) =>
    CatalogCategory(id: c.id, name: c.name);

LiveChannel providerChannelToDomain(
  ProviderChannel c, {
  List<EpgEntry> epg = const [],
  DateTime? now,
}) {
  final name = cleanDisplayName(c.name, keepQuality: true);
  final t = now ?? DateTime.now();
  EpgEntry? current;
  EpgEntry? next;
  for (final e in epg) {
    if (current == null && e.isOnAt(t)) {
      current = e;
    } else if (e.start.isAfter(t) && (next == null || e.start.isBefore(next.start))) {
      next = e;
    }
  }
  return LiveChannel(
    id: c.id,
    name: name,
    code: c.number != null && c.number! > 0 ? '${c.number}' : 'LIVE',
    nowTitle: current?.title ?? name,
    nextTitle: next?.title ?? '',
    progress: current?.progressAt(t) ?? 0.5,
    imageUrl: _url(c.logoUrl),
  );
}

MediaItem providerMovieToDomain(ProviderMovie m, {ProviderMovieDetails? details}) => MediaItem(
      id: m.id,
      title: m.name,
      kind: MediaKind.movie,
      year: m.year,
      rating: _rating(m.rating),
      posterUrl: _url(m.posterUrl),
      backdropUrl: _url(details?.backdropUrl),
      synopsis: _text(details?.plot),
      genres: details?.genres ?? const [],
      durationLabel: formatRuntimeLabel(runtimeMinutesFromDurationSec(details?.durationSec)),
      containerExtension: m.stream.extension,
      categoryId: m.categoryId,
      addedSec: m.addedSec,
    );

MediaItem providerSeriesToDomain(ProviderSeries s) => MediaItem(
      id: s.id,
      title: s.name,
      kind: MediaKind.series,
      year: s.year,
      rating: _rating(s.rating),
      posterUrl: _url(s.posterUrl),
      backdropUrl: _url(s.backdropUrl),
      synopsis: _text(s.plot),
      genres: s.genres,
      categoryId: s.categoryId,
      seriesId: s.id,
      addedSec: s.addedSec,
    );

Episode providerEpisodeToDomain(ProviderEpisode e) => Episode(
      id: e.id,
      seriesId: e.seriesId,
      season: e.season,
      number: e.number,
      title: cleanDisplayName(e.title),
      // Empty when the panel sends no duration (never invent one).
      durationLabel: formatRuntimeLabel(runtimeMinutesFromDurationSec(e.durationSec)) ?? '',
      synopsis: _text(e.plot),
      stillUrl: _url(e.stillUrl),
      containerExtension: e.stream.extension,
    );

/// Panels send 0 for "no rating"; out-of-range values are dropped.
double? _rating(double? r) => (r == null || !r.isFinite || r <= 0 || r > 10) ? null : r;

String? _url(String? u) {
  final s = u?.trim() ?? '';
  return (s.startsWith('http://') || s.startsWith('https://')) ? s : null;
}

String? _text(String? t) {
  final s = t?.trim() ?? '';
  return s.isEmpty ? null : s;
}
