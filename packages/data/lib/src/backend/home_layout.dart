// Home screen layout from the published app config (`get_app_config` → "home").
// Content is referenced portably; the app resolves every [ContentRef] against
// the user's own panel catalog and hides what the user cannot play.

import '../remote/json_read.dart';
import 'json_util.dart';

enum HomeSectionType {
  heroBanners('hero_banners'),
  continueWatching('continue_watching'),
  top10('top10'),
  newReleases('new_releases'),
  recentlyAdded('recently_added'),
  trending('trending'),
  popular('popular'),
  liveNow('live_now'),
  favorites('favorites'),
  recentlyWatched('recently_watched'),
  recommended('recommended'),
  category('category'),
  genre('genre'),
  collection('collection'),
  matchesLive('matches_live'),
  matchesUpcoming('matches_upcoming'),
  custom('custom'),
  unknown('unknown');

  const HomeSectionType(this.wire);
  final String wire;
}

/// Where a section's items come from (computed on device unless [manual]).
enum SectionSource {
  auto('auto'),
  providerAdded('provider_added'),
  providerRating('provider_rating'),
  providerCategory('provider_category'),
  manual('manual'),
  random('random'),
  watchStats('watch_stats'),
  unknown('unknown');

  const SectionSource(this.wire);
  final String wire;
}

enum ContentKind {
  live('live'),
  movie('movie'),
  series('series'),
  mixed('mixed'),
  link('link'),
  unknown('unknown');

  const ContentKind(this.wire);
  final String wire;
}

enum SectionLayout { rail, wideRail, grid, hero, ranked, circles, cards }

T _byWire<T extends Enum>(Object? v, List<T> values, String Function(T) wire, T fallback) {
  final s = jsonStr(v);
  for (final e in values) {
    if (wire(e) == s) return e;
  }
  return fallback;
}

HomeSectionType parseSectionType(Object? v) =>
    _byWire(v, HomeSectionType.values, (e) => e.wire, HomeSectionType.unknown);
SectionSource parseSectionSource(Object? v) =>
    _byWire(v, SectionSource.values, (e) => e.wire, SectionSource.unknown);
ContentKind parseContentKind(Object? v) =>
    _byWire(v, ContentKind.values, (e) => e.wire, ContentKind.unknown);

SectionLayout parseLayout(Object? v) => switch (jsonStr(v)) {
      'wide_rail' => SectionLayout.wideRail,
      'grid' => SectionLayout.grid,
      'hero' => SectionLayout.hero,
      'ranked' => SectionLayout.ranked,
      'circles' => SectionLayout.circles,
      'cards' => SectionLayout.cards,
      _ => SectionLayout.rail,
    };

/// A pointer to one title/channel, matched against the user's panel in this order:
/// panel item id (same provider family) → TMDB id → title.
class ContentRef {
  const ContentRef({
    required this.kind,
    this.panelKey,
    this.panelItemId,
    this.tmdbId,
    this.matchTitle,
    this.title,
    this.imageUrl,
    this.deepLink,
  });

  final ContentKind kind;
  final String? panelKey;
  final String? panelItemId;
  final int? tmdbId;
  final String? matchTitle;
  final String? title;
  final String? imageUrl;
  final String? deepLink;

  bool get isUsable =>
      deepLink != null || panelItemId != null || tmdbId != null || matchTitle != null;

  factory ContentRef.fromJson(Map<String, dynamic> j) => ContentRef(
        kind: parseContentKind(j['kind']),
        panelKey: jsonStr(j['panel']),
        panelItemId: jsonStr(j['panel_id']),
        tmdbId: jsonInt(j['tmdb']),
        matchTitle: jsonStr(j['match']),
        title: jsonStr(j['title']),
        imageUrl: jsonStr(j['image']),
        deepLink: jsonStr(j['link']),
      );
}

class HomeSection {
  const HomeSection({
    required this.id,
    required this.title,
    required this.type,
    required this.source,
    required this.layout,
    required this.limit,
    this.subtitle,
    this.kind = ContentKind.mixed,
    this.params = const {},
    this.top10ListId,
    this.requiresLogin = false,
    this.items = const [],
  });

  final String id;
  final String title;
  final String? subtitle;
  final HomeSectionType type;
  final ContentKind kind;
  final SectionSource source;
  final Map<String, dynamic> params;
  final SectionLayout layout;
  final int limit;
  final String? top10ListId;
  final bool requiresLogin;
  final List<ContentRef> items;

  /// e.g. `params.days` for provider_added/provider_rating rails.
  int? intParam(String key) => jsonInt(params[key]);
  String? strParam(String key) => jsonStr(params[key]);

  /// Null when the entry is unusable (missing id/title or a type this app doesn't know).
  static HomeSection? tryParse(Map<String, dynamic> j) {
    final id = jsonStr(j['id']);
    final title = jsonStr(j['title']);
    final type = parseSectionType(j['type']);
    if (id == null || title == null || type == HomeSectionType.unknown) return null;
    return HomeSection(
      id: id,
      title: title,
      subtitle: jsonStr(j['subtitle']),
      type: type,
      kind: parseContentKind(j['kind']) == ContentKind.unknown
          ? ContentKind.mixed
          : parseContentKind(j['kind']),
      source: parseSectionSource(j['source']),
      params: jsonMap(j['params']),
      layout: parseLayout(j['layout']),
      limit: (jsonInt(j['limit']) ?? 20).clamp(1, 100),
      top10ListId: jsonStr(j['top10']),
      requiresLogin: jsonBool(j['login']) ?? false,
      items: jsonMapList(j['items']).map(ContentRef.fromJson).where((r) => r.isUsable).toList(),
    );
  }
}

enum BannerAction { none, content, category, screen, url }

class HomeBanner {
  const HomeBanner({
    required this.id,
    required this.title,
    required this.imageUrl,
    this.subtitle,
    this.imageUrlTv,
    this.cta,
    this.action = BannerAction.none,
    this.actionValue,
    this.content,
    this.requiresLogin = false,
  });

  final String id;
  final String title;
  final String? subtitle;
  final String imageUrl;
  final String? imageUrlTv;
  final String? cta;
  final BannerAction action;
  final String? actionValue;
  final ContentRef? content;
  final bool requiresLogin;

  String imageFor({required bool tv}) => tv ? (imageUrlTv ?? imageUrl) : imageUrl;

  static HomeBanner? tryParse(Map<String, dynamic> j) {
    final id = jsonStr(j['id']);
    final title = jsonStr(j['title']);
    final image = jsonStr(j['image']);
    if (id == null || title == null || image == null) return null;
    final action = jsonEnum(j['action'], BannerAction.values, BannerAction.none);
    final ref = ContentRef(
      kind: parseContentKind(j['kind']),
      panelKey: jsonStr(j['panel']),
      panelItemId: jsonStr(j['panel_id']),
      tmdbId: jsonInt(j['tmdb']),
    );
    return HomeBanner(
      id: id,
      title: title,
      subtitle: jsonStr(j['subtitle']),
      imageUrl: image,
      imageUrlTv: jsonStr(j['image_tv']),
      cta: jsonStr(j['cta']),
      action: action,
      actionValue: jsonStr(j['value']),
      content: ref.isUsable ? ref : null,
      requiresLogin: jsonBool(j['login']) ?? false,
    );
  }
}

enum Top10Source {
  manual('manual'),
  providerAdded('provider_added'),
  providerRating('provider_rating'),
  watchStats('watch_stats'),
  unknown('unknown');

  const Top10Source(this.wire);
  final String wire;
}

class Top10Entry {
  const Top10Entry({required this.rank, required this.ref});
  final int rank;
  final ContentRef ref;
}

class Top10List {
  const Top10List({
    required this.id,
    required this.title,
    required this.kind,
    required this.source,
    this.params = const {},
    this.country,
    this.items = const [],
  });

  final String id;
  final String title;
  final ContentKind kind;
  final Top10Source source;
  final Map<String, dynamic> params;
  final String? country;

  /// Admin picks (source = manual). Other sources are computed on device.
  final List<Top10Entry> items;

  static Top10List? tryParse(Map<String, dynamic> j) {
    final id = jsonStr(j['id']);
    final title = jsonStr(j['title']);
    if (id == null || title == null) return null;
    final items = <Top10Entry>[];
    for (final i in jsonMapList(j['items'])) {
      final rank = jsonInt(i['rank']);
      final ref = ContentRef.fromJson(i);
      if (rank != null && rank >= 1 && rank <= 10 && ref.isUsable) {
        items.add(Top10Entry(rank: rank, ref: ref));
      }
    }
    items.sort((a, b) => a.rank.compareTo(b.rank));
    return Top10List(
      id: id,
      title: title,
      kind: parseContentKind(j['kind']),
      source: _byWire(j['source'], Top10Source.values, (e) => e.wire, Top10Source.unknown),
      params: jsonMap(j['params']),
      country: jsonStr(j['country']),
      items: items,
    );
  }
}

class HomeLayout {
  const HomeLayout({this.sections = const [], this.banners = const [], this.top10 = const []});

  final List<HomeSection> sections;
  final List<HomeBanner> banners;
  final List<Top10List> top10;

  static const empty = HomeLayout();

  Top10List? top10ById(String? id) {
    if (id == null) return null;
    for (final t in top10) {
      if (t.id == id) return t;
    }
    return null;
  }

  factory HomeLayout.fromJson(Map<String, dynamic> j) => HomeLayout(
        sections: jsonMapList(j['sections']).map(HomeSection.tryParse).whereType<HomeSection>().toList(),
        banners: jsonMapList(j['banners']).map(HomeBanner.tryParse).whereType<HomeBanner>().toList(),
        top10: jsonMapList(j['top10']).map(Top10List.tryParse).whereType<Top10List>().toList(),
      );
}
