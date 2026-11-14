import 'dart:async';

import 'package:data/data.dart'
    show Diag, EpgProgramDto, FavoriteCategories, RemoteCatalogRepository;
import 'package:design_system/design_system.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../core/tv_clock.dart';
import '../../core/library_controller.dart';
import '../../core/providers.dart';
import '../../core/tv_live_zap.dart';
import '../../core/tv_locale.dart';
import '../../core/tv_program_reminders.dart';
import '../../core/tv_session.dart';
import '../../widgets/focus_tile.dart';
import '../../widgets/tv_arrange_packages.dart';
import '../../widgets/tv_poster.dart';
import '../../widgets/tv_ui.dart';
import 'tv_live_preview.dart';

/// Figma: APP 4K TV Live TV & EPG V2. Preview panel for the focused
/// channel, a category column and the channel list. Programme times are not
/// shown: the provider feed has no guide data for these channels.
class TvLiveScreen extends ConsumerStatefulWidget {
  const TvLiveScreen({
    super.key,
    this.sportsOnly = false,
    this.kidsOnly = false,
  });

  /// Sports tab: the same categories + channel list + preview layout,
  /// focus and Back-twice playback flow, limited to sports categories.
  final bool sportsOnly;

  /// Kids → Live TV: the same layout limited to children's categories, with
  /// its own Favourites (client 21 Oct: "Kids live channels in the same
  /// layout as Live TV", "Kids favourites separate").
  final bool kidsOnly;

  @override
  ConsumerState<TvLiveScreen> createState() => _TvLiveScreenState();
}

class _TvLiveScreenState extends ConsumerState<TvLiveScreen>
    with WidgetsBindingObserver {
  static const _channelRowH = 64.0;
  static const _pageSize = 100;

  List<CatalogCategory> _categories = const [];
  int _catIndex = 0;

  /// "Favourites" first in Live TV and in Sports once the profile has a
  /// favourite channel there (client 20 Oct #10). Built from the saved
  /// favourites; not part of the package order.
  static const _favId = '__favourites__';
  Set<String> _sportsIds = const {};
  Set<String> _kidsIds = const {};
  final Map<String, List<MediaItem>> _channels = {};
  final Set<String> _loading = {};

  /// Packages whose load failed: "Could not load · Retry", never shown as
  /// an empty package (client 17 Oct: a failure looked like "0 channels").
  final Set<String> _failed = {};
  MediaItem? _focused;
  bool _booting = true;
  Object? _error;
  Timer? _catDebounce;
  final ScrollController _channelScroll = ScrollController();
  final FocusNode _firstChannel = FocusNode(debugLabel: 'live-first-channel');
  // The open package's tile: Right from any channel lands here (customers,
  // 4 Nov: "cannot move from the channel list to the package list").
  final FocusNode _openCatFocus = FocusNode(debugLabel: 'live-open-package');
  bool _wantChannelFocus = false;

  late final TvLivePreviewController _preview = TvLivePreviewController(
    auth: ref.read(tvAuthRepositoryProvider),
    media: ref.read(tvMediaRepositoryProvider),
    profileId: ref.read(tvSessionProvider).activeProfileId,
  );
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_boot());
  }

  /// Hidden (another tab, the player route on top): release the preview's
  /// provider connection. Offstage routes/branches have tickers disabled.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible == _visible) return;
    _visible = visible;
    if (visible) {
      _preview.resume(_focused);
      _previewSelectedCategory();
    } else {
      _preview.suspend();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_visible) {
        _preview.resume(_focused);
        _previewSelectedCategory();
      }
    } else {
      _preview.suspend();
    }
  }

  /// Moving over the channels only shows the channel's info: it never starts
  /// one (customers, 4 Nov: "arrows move the focus only, OK confirms"). OK
  /// plays it fullscreen. [_autoPreview] brings the muted preview back.
  static const _autoPreview = false;

  void _setFocused(MediaItem? c) {
    setState(() => _focused = c);
    if (_visible && _autoPreview) _preview.select(c);
  }

  /// With focus on a package, the preview plays that package's first
  /// channel (client 16 Oct: "the window shows a channel image; it should
  /// play video"). It used to open only after focus rested on a channel.
  void _previewSelectedCategory() {
    if (!_autoPreview) return;
    if (!_visible || _focused != null || _categories.isEmpty) return;
    final list = _channels[_categories[_catIndex].id];
    if (list == null || list.isEmpty) return;
    _preview.select(list.first);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _preview.dispose();
    _catDebounce?.cancel();
    _channelScroll.dispose();
    _firstChannel.dispose();
    _openCatFocus.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    try {
      var cats = await ref
          .read(catalogRepositoryProvider)
          .getCategories(MediaKind.live);
      _sportsIds = {
        for (final c in cats)
          if (RemoteCatalogRepository.isSportsCategory(c)) c.id,
      };
      _kidsIds = {
        for (final c in cats)
          if (!RemoteCatalogRepository.isSportsCategory(c) &&
              KidsPanelCategories.looksKids(c.name))
            c.id,
      };
      // Sports channels live only in the Sports tab (client 16 Oct #11).
      cats = [
        for (final c in cats)
          if (widget.kidsOnly
              ? _kidsIds.contains(c.id)
              : RemoteCatalogRepository.isSportsCategory(c) ==
                    widget.sportsOnly)
            c,
      ];
      final unique = <CatalogCategory>[];
      final seen = <String>{};
      // Unique by id. Cleaned names can collide ("THMANYAH" and
      // "THMANYAH ●" are two packages): keep both, number the repeat.
      final names = <String, int>{};
      for (final c in cats) {
        if (!seen.add(c.id)) continue;
        final key = c.name.toLowerCase();
        final n = (names[key] ?? 0) + 1;
        names[key] = n;
        unique.add(
          n == 1
              ? c
              : CatalogCategory(
                  id: c.id,
                  name: '${c.name} $n',
                  isSports: c.isSports,
                ),
        );
      }
      // The profile's package order (client 17 Oct), shared with phones.
      _providerCategories = unique;
      var ordered = unique;
      final pid = ref.read(tvSessionProvider).activeProfileId;
      if (pid != null && pid.isNotEmpty) {
        final ids = await ref
            .read(categoryOrderStoreProvider)
            .load(pid, 'live');
        ordered = applyCategoryOrder(unique, ids);
      }
      if (!mounted) return;
      setState(() {
        _categories = _withFavourites(ordered);
        _booting = false;
      });
      if (_categories.isNotEmpty) unawaited(_load(_categories.first.id));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _booting = false;
      });
    }
  }

  /// Client 20 Oct T9 ("some channels do not appear"): only the first
  /// [_pageSize] channels of a package were ever loaded. The rest now
  /// follow page by page, appended in provider order.
  Future<void> _loadRest(String categoryId, String cursor) async {
    final repo = ref.read(catalogRepositoryProvider);
    String? next = cursor;
    for (var n = 0; next != null && next.isNotEmpty && n < 40; n++) {
      final CatalogPage<MediaItem> page;
      try {
        page = await repo.browse(
          kind: MediaKind.live,
          categoryId: categoryId,
          cursor: next,
          limit: _pageSize,
        );
      } catch (e) {
        Diag.dev(
          'LIVE package more failed id=$categoryId page=${n + 2} err=$e',
        );
        return;
      }
      if (!mounted) return;
      final have = _channels[categoryId];
      if (have == null) {
        // First page not stored yet (still in setState); retry shortly.
        await Future<void>.delayed(const Duration(milliseconds: 200));
        if (!mounted || _channels[categoryId] == null) return;
      }
      final known = {for (final m in _channels[categoryId]!) m.id};
      final more = [
        for (final m in page.items)
          if (!isProviderAdOrHeaderChannel(m.title) && known.add(m.id)) m,
      ];
      if (more.isNotEmpty) {
        setState(
          () => _channels[categoryId] = [..._channels[categoryId]!, ...more],
        );
      }
      next = page.nextCursor;
    }
    Diag.dev(
      'LIVE package all pages id=$categoryId '
      'channels=${_channels[categoryId]?.length ?? 0}',
    );
  }

  Future<void> _load(String categoryId, {int attempt = 0}) async {
    if (categoryId == _favId) return;
    if (_channels.containsKey(categoryId) || !_loading.add(categoryId)) {
      return;
    }
    setState(() => _failed.remove(categoryId));
    try {
      final repo = ref.read(catalogRepositoryProvider);
      var page = await repo.browse(
        kind: MediaKind.live,
        categoryId: categoryId,
        limit: _pageSize,
      );
      if (!mounted) return;
      var items = page.items
          .where((m) => !isProviderAdOrHeaderChannel(m.title))
          .toList();
      // A first page of banner rows only is not an empty package.
      var guard = 0;
      while (items.isEmpty && page.hasMore && guard++ < 5) {
        page = await repo.browse(
          kind: MediaKind.live,
          categoryId: categoryId,
          cursor: page.nextCursor,
          limit: _pageSize,
        );
        if (!mounted) return;
        items = page.items
            .where((m) => !isProviderAdOrHeaderChannel(m.title))
            .toList();
      }
      if (page.hasMore) unawaited(_loadRest(categoryId, page.nextCursor!));
      if (items.isEmpty) {
        // Client 16 Oct #6: no empty categories. Drop it from the column
        // and keep the selection on the same visible category.
        _dropEmptyCategory(categoryId);
        return;
      }
      setState(() => _channels[categoryId] = items);
      _focusChannelsIfWanted();
      if (_categories.isNotEmpty && _categories[_catIndex].id == categoryId) {
        _previewSelectedCategory();
      }
    } catch (e) {
      Diag.dev(
        'LIVE package load failed id=$categoryId attempt=$attempt '
        'type=${e.runtimeType} err=$e',
      );
      if (!mounted) return;
      // Signed out on the server (device removed at the device limit, 21 Oct
      // TCL): go to sign-in instead of "could not be loaded" on every package.
      unawaited(ref.read(tvSessionProvider.notifier).handleAuthLoss(e));
      if (attempt < 1) {
        _loading.remove(categoryId);
        await Future<void>.delayed(Duration(milliseconds: 700 * (attempt + 1)));
        if (!mounted) return;
        return _load(categoryId, attempt: attempt + 1);
      }
      setState(() => _failed.add(categoryId));
    } finally {
      _loading.remove(categoryId);
      if (mounted) setState(() {});
    }
  }

  void _dropEmptyCategory(String categoryId) {
    final idx = _categories.indexWhere((c) => c.id == categoryId);
    if (idx < 0) return;
    setState(() {
      final selectedId = _categories[_catIndex].id;
      _categories = [..._categories]..removeAt(idx);
      if (_categories.isEmpty) {
        _catIndex = 0;
        return;
      }
      final keep = _categories.indexWhere((c) => c.id == selectedId);
      _catIndex = keep >= 0 ? keep : idx.clamp(0, _categories.length - 1);
      _focused = null;
    });
    if (_categories.isNotEmpty) {
      unawaited(_load(_categories[_catIndex].id));
    }
  }

  List<CatalogCategory> _providerCategories = const [];

  /// Favourite live channels for this tab (Sports or general Live TV).
  List<MediaItem> _favouriteChannels(LibraryState lib) {
    final seen = <String>{};
    return [
      for (final m in lib.liked)
        if ((m.kind == MediaKind.live || m.kind == MediaKind.sports) &&
            _favouriteBelongsHere(m) &&
            seen.add(m.id))
          m,
    ];
  }

  /// Kids channel favourites show in Kids only; sports ones in Sports only;
  /// the rest in Live TV.
  bool _favouriteBelongsHere(MediaItem m) {
    final sports = RemoteCatalogRepository.isSportsHit(m, _sportsIds);
    final cat = m.categoryId ?? FavoriteCategories.categoryOf(m.id);
    // No category from the server or this device: the channel name decides,
    // as for Sports (MBC TOON, Spacetoon…; TCL 21 Oct showed it nowhere).
    final kids =
        !sports &&
        (cat != null
            ? _kidsIds.contains(cat)
            : KidsPanelCategories.looksKids(m.title));
    if (widget.kidsOnly) return kids;
    if (widget.sportsOnly) return sports;
    return !sports && !kids;
  }

  /// [cats] with the Favourites category first when there are favourites.
  List<CatalogCategory> _withFavourites(List<CatalogCategory> cats) {
    final rest = [
      for (final c in cats)
        if (c.id != _favId) c,
    ];
    final favs = _favouriteChannels(ref.read(libraryProvider));
    if (favs.isEmpty) {
      _channels.remove(_favId);
      return rest;
    }
    _channels[_favId] = favs;
    final copy = AppCopy.ofLanguage(ref.read(tvLanguageProvider));
    return [
      CatalogCategory(
        id: _favId,
        name: copy.favoritesCategory,
        isSports: widget.sportsOnly,
      ),
      ...rest,
    ];
  }

  /// Favourites changed: refresh the category, keep the selection.
  void _syncFavourites() {
    if (_booting || !mounted) return;
    final selectedId = _categories.isEmpty ? null : _categories[_catIndex].id;
    final next = _withFavourites(_categories);
    setState(() {
      _categories = next;
      final keep = next.indexWhere((c) => c.id == selectedId);
      _catIndex = keep >= 0 ? keep : 0;
    });
  }

  Future<void> _arrange(AppCopy copy) async {
    final ids = await showTvArrangePackages(
      context,
      categories: [
        for (final c in _categories)
          if (c.id != _favId) c,
      ],
      label: (raw) => raw,
      copy: copy,
    );
    if (ids == null || !mounted) return;
    final pid = ref.read(tvSessionProvider).activeProfileId;
    final store = ref.read(categoryOrderStoreProvider);
    var saved = ids;
    if (pid != null && pid.isNotEmpty && ids.isNotEmpty) {
      // Live TV and Sports share one order: keep the other tab's packages.
      final previous = await store.load(pid, 'live');
      final shown = ids.toSet();
      saved = [
        ...ids,
        for (final id in previous)
          if (!shown.contains(id)) id,
      ];
    }
    if (!mounted) return;
    final selectedId = _categories.isEmpty ? null : _categories[_catIndex].id;
    setState(() {
      _categories = _withFavourites(
        applyCategoryOrder(_providerCategories, ids),
      );
      final keep = _categories.indexWhere((c) => c.id == selectedId);
      _catIndex = keep < 0 ? 0 : keep;
    });
    if (pid != null && pid.isNotEmpty) await store.save(pid, 'live', saved);
  }

  void _selectCategory(int i) {
    if (i == _catIndex) return;
    setState(() {
      _catIndex = i;
      _focused = null;
    });
    if (_channelScroll.hasClients) _channelScroll.jumpTo(0);
    unawaited(_load(_categories[i].id));
    _previewSelectedCategory();
  }

  /// Moving through the packages changes nothing (customers, 4 Nov); OK
  /// opens the package ([_selectCategory] + into its channels).
  void _onCategoryFocus(int i) {
    _catDebounce?.cancel();
  }

  /// Left from the packages: into the channel list. While the list is
  /// still loading, focus moves there as soon as it arrives (before, Right
  /// jumped to the Favorite button above).
  void _enterChannels() {
    _catDebounce?.cancel();
    final focusedCat = _categories.isEmpty ? null : _categories[_catIndex];
    if (focusedCat == null) return;
    _wantChannelFocus = true;
    _focusChannelsIfWanted();
  }

  void _focusChannelsIfWanted() {
    if (!_wantChannelFocus || _categories.isEmpty) return;
    final list = _channels[_categories[_catIndex].id];
    if (list == null) return;
    _wantChannelFocus = false;
    if (list.isEmpty) return;
    if (_firstChannel.context != null) {
      _firstChannel.requestFocus();
      return;
    }
    // List not built yet: focus it on the next frame (and make sure one runs;
    // a post-frame callback alone waited for the next key press).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _firstChannel.requestFocus();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _play(MediaItem channel, List<MediaItem> row) async {
    // Free the preview's provider connection before fullscreen starts.
    _preview.suspend();
    try {
      await _preview.release().timeout(const Duration(seconds: 4));
    } catch (_) {}
    if (!mounted) return;
    openTvLiveChannel(
      context,
      ref,
      channel,
      row,
      title: _categories.isEmpty ? null : _categories[_catIndex].name,
    );
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppCopy.ofLanguage(ref.watch(tvLanguageProvider));
    ref.listen<LibraryState>(libraryProvider, (prev, next) {
      if (prev?.liked != next.liked) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _syncFavourites());
      }
    });
    if (_booting) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(36, 16, 36, 24),
        child: Column(
          children: [
            AppShimmer.block(height: 168, radius: BorderRadius.circular(18)),
            const SizedBox(height: 16),
            Expanded(
              child: AppShimmer.block(radius: BorderRadius.circular(18)),
            ),
          ],
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              copy.noLiveChannels,
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TvButton(
              autofocus: true,
              icon: Icons.refresh_rounded,
              label: copy.retry,
              onTap: () {
                setState(() {
                  _error = null;
                  _booting = true;
                });
                unawaited(_boot());
              },
            ),
          ],
        ),
      );
    }
    if (_categories.isEmpty) {
      return Center(
        child: Text(
          copy.noLiveChannels,
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }

    final cat = _categories[_catIndex];
    final channels = _channels[cat.id];
    final failed = channels == null && _failed.contains(cat.id);
    final loading = channels == null && !failed;
    // First package on opening the screen too (the load can finish before
    // the tab is visible). select() ignores a channel already selected.
    if (_focused == null && channels != null && channels.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _previewSelectedCategory();
      });
    }
    final preview =
        _focused ??
        ((channels != null && channels.isNotEmpty) ? channels.first : null);
    final previewIndex = preview == null || channels == null
        ? null
        : channels.indexWhere((c) => c.id == preview.id);

    // Client 16 Oct #17: preview + channel info on the left, categories and
    // a full-height channel list on the right (the list used to get only
    // the bottom third of the screen under a large banner).
    return Padding(
      padding: const EdgeInsets.fromLTRB(36, 12, 36, 20),
      // Packages first in reading order, as on LG (client 2 Nov #7):
      // English = packages | channels | preview (left to right), Arabic =
      // preview | channels | packages (packages on the right, as before).
      // Text inside each column keeps the app's direction.
      child: Row(
        textDirection: Directionality.of(context) == TextDirection.rtl
            ? TextDirection.ltr
            : TextDirection.rtl,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 300,
            child: _PreviewPanel(
              preview: _preview,
              channel: preview,
              channelNumber: previewIndex == null || previewIndex < 0
                  ? null
                  : previewIndex + 1,
              categoryLabel: cat.name,
              onWatch: preview == null || channels == null
                  ? null
                  : () => _play(preview, channels),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: TvGlass(
              radius: 18,
              // Client 16 Oct: packages first, their channels in the middle,
              // preview in the small window — physically preview | channels
              // | packages in English and Arabic (RTL order of the children
              // below; text in each column keeps the app direction).
              child: Row(
                // Packages on the reading side: right in Arabic, left in English.
                textDirection: Directionality.of(context),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 210,
                    child: _CategoryColumn(
                      title: copy.categories,
                      // Provider names as-is: the shared label map turned every
                      // sports package into just "Sports".
                      labels: [for (final c in _categories) c.name],
                      // Loaded categories show what the list shows: the server
                      // count includes the provider's "#####" separator rows
                      // the list hides (TCL 21 Oct: SOLO SPORT 33 vs 32).
                      counts: [
                        for (final c in _categories)
                          _channels[c.id]?.length ??
                              ref
                                  .watch(catalogCountsProvider)
                                  .valueOrNull
                                  ?.live
                                  .byCategory[c.id],
                      ],
                      arrangeLabel: copy.arrangePackages,
                      sortText: copy.sortLabel,
                      onArrange: _categories.length < 2
                          ? null
                          : () => _arrange(copy),
                      selected: _catIndex,
                      selectedFocus: _openCatFocus,
                      onFocus: _onCategoryFocus,
                      // OK opens the package and moves into its channels.
                      onSelect: (i) {
                        _selectCategory(i);
                        _enterChannels();
                      },
                      // Left only moves into the open package's channels.
                      onEnterChannels: (_) => _enterChannels(),
                    ),
                  ),
                  Container(width: 1, color: Colors.white10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
                          child: Row(
                            children: [
                              Icon(
                                Icons.live_tv_rounded,
                                size: 18,
                                color: AppColors.cyan,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                // While a category loads, the server count
                                // (it said "CHANNELS (0)" over an empty list,
                                // CEO video 21 Oct).
                                copy.channelsCount(
                                  channels?.length ??
                                      ref
                                          .watch(catalogCountsProvider)
                                          .valueOrNull
                                          ?.live
                                          .byCategory[cat.id] ??
                                      0,
                                ),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: loading
                              ? Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      AppLoader.inline(size: 40),
                                      const SizedBox(height: 14),
                                      Text(
                                        '${copy.loading}…',
                                        style: TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : failed
                              ? Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        copy.packageLoadFailed,
                                        style: TextStyle(
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      TvButton(
                                        label: copy.retry,
                                        icon: Icons.refresh_rounded,
                                        onTap: () => unawaited(_load(cat.id)),
                                      ),
                                    ],
                                  ),
                                )
                              : channels!.isEmpty
                              ? Center(
                                  child: Text(
                                    copy.noLiveChannels,
                                    style: TextStyle(
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                )
                              : FocusTraversalGroup(
                                  child: ListView.builder(
                                    controller: _channelScroll,
                                    padding: const EdgeInsets.fromLTRB(
                                      12,
                                      0,
                                      12,
                                      12,
                                    ),
                                    itemExtent: _channelRowH,
                                    scrollCacheExtent:
                                        const ScrollCacheExtent.pixels(800),
                                    itemCount: channels.length,
                                    itemBuilder: (_, i) {
                                      final c = channels[i];
                                      return _ChannelRow(
                                        focusNode: i == 0
                                            ? _firstChannel
                                            : null,
                                        number: i + 1,
                                        channel: c,
                                        isLast: i == channels.length - 1,
                                        onRight: () => _openCatFocus.requestFocus(),
                                        onFocus: () => _setFocused(c),
                                        onTap: () => _play(c, channels),
                                      );
                                    },
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewPanel extends ConsumerWidget {
  const _PreviewPanel({
    required this.preview,
    required this.channel,
    required this.channelNumber,
    required this.categoryLabel,
    required this.onWatch,
  });

  final TvLivePreviewController preview;
  final MediaItem? channel;
  final int? channelNumber;
  final String categoryLabel;
  final VoidCallback? onWatch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = AppCopy.ofLanguage(ref.watch(tvLanguageProvider));
    final c = channel;
    final fav = c != null && ref.watch(libraryProvider).ratingFor(c.id) == 1;
    final arabic = (c?.titleArabic ?? '').trim();
    final chLabel = channelNumber == null
        ? categoryLabel
        : 'CH $channelNumber  ·  $categoryLabel';

    return TvGlass(
      radius: 18,
      tint: AppColors.cyan,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Preview window: muted live picture of the focused channel
          // (one connection, see TvLivePreviewController); logo meanwhile.
          // Flexible: it shrinks when the guide and "Remind me" need the
          // room, so Watch Fullscreen / Favorite are never cut off at the
          // bottom (TCL 21 Oct, CEO video).
          // Top-aligned like Sports: without a guide the free space used to
          // centre the preview and leave a gap above it.
          Flexible(
            child: Align(
              alignment: Alignment.topCenter,
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.cyan.withValues(alpha: 0.35),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (c != null)
                        Padding(
                          padding: const EdgeInsets.all(18),
                          child: RemoteImage(
                            url: c.posterUrl ?? c.backdropUrl,
                            fit: BoxFit.contain,
                            memCacheWidth: 640,
                          ),
                        )
                      else
                        ColoredBox(color: AppColors.surfaceElevated),
                      // Live picture of the focused channel once it rests there
                      // (client #12); the logo stays underneath while it opens.
                      ListenableBuilder(
                        listenable: preview,
                        builder: (_, _) {
                          final v = preview.controllerFor(c?.id);
                          if (v == null) return const SizedBox.shrink();
                          return ColoredBox(
                            color: Colors.black,
                            child: Center(
                              child: AspectRatio(
                                aspectRatio: v.value.aspectRatio > 0
                                    ? v.value.aspectRatio
                                    : 16 / 9,
                                child: VideoPlayer(v),
                              ),
                            ),
                          );
                        },
                      ),
                      const PositionedDirectional(
                        top: 10,
                        end: 10,
                        child: TvPill(
                          '● LIVE',
                          tone: TvPillTone.live,
                          compact: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              TvPill(chLabel, tone: TvPillTone.muted, compact: true),
              for (final b in (c?.badges ?? const []).take(2))
                TvPill(b, tone: TvPillTone.muted, compact: true),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            c?.displayTitle ?? '—',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 26,
              height: 1.1,
            ),
          ),
          if (arabic.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              arabic,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TvUi.titleArabic.copyWith(fontSize: 16),
              textDirection: TextDirection.rtl,
            ),
          ],
          const SizedBox(height: 8),
          if ((c?.synopsis ?? c?.subtitle ?? '').trim().isNotEmpty)
            Text(
              (c?.synopsis ?? c?.subtitle ?? '').trim(),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TvUi.body,
            ),
          // Now / next from the guide once focus rests (client 16 Oct #08).
          if (c != null)
            ListenableBuilder(
              listenable: preview,
              builder: (_, _) => preview.settledId == c.id
                  ? _EpgNowNext(channel: c, copy: copy)
                  : const SizedBox.shrink(),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _PanelButton(
                  primary: true,
                  icon: Icons.play_arrow_rounded,
                  label: copy.watchFullscreen,
                  onTap: onWatch,
                ),
              ),
              const SizedBox(width: 10),
              _PanelButton(
                icon: fav ? Icons.star_rounded : Icons.star_border_rounded,
                label: fav ? copy.favorited : copy.favorite,
                onTap: c == null
                    ? null
                    : () => ref
                          .read(libraryProvider.notifier)
                          .setRating(c.id, 1, item: c),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EpgNowNext extends ConsumerWidget {
  const _EpgNowNext({required this.channel, required this.copy});

  final MediaItem channel;
  final AppCopy copy;

  String _hm(BuildContext context, DateTime t) => tvClock12(
        t.hour,
        t.minute,
        arabic: Localizations.localeOf(context).languageCode == 'ar',
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progs =
        ref.watch(liveEpgProvider(channel.id)).valueOrNull ?? const [];
    if (progs.isEmpty) return const SizedBox.shrink();
    final now = DateTime.now();
    EpgProgramDto? cur;
    EpgProgramDto? next;
    for (final p in progs) {
      if (cur == null && p.isOnAt(now)) {
        cur = p;
      } else if (p.startAt.isAfter(now)) {
        next ??= p;
      }
    }
    if (cur == null && next == null) return const SizedBox.shrink();
    final reminders = ref.watch(tvProgramRemindersProvider);
    Widget line(String label, EpgProgramDto p) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label  ${_hm(context, p.startAt)}  ',
              style: TextStyle(
                color: AppColors.cyan,
                fontWeight: FontWeight.w800,
              ),
            ),
            TextSpan(text: p.title),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TvUi.body.copyWith(fontSize: 14),
      ),
    );
    final n = next;
    final set = n != null && reminders.isSet(channel.id, n.startAt);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        if (cur != null) line(copy.epgNow, cur),
        if (n != null) line(copy.epgNext, n),
        if (n != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: TvButton(
              icon: set
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_none_rounded,
              label: set ? copy.reminderSet : copy.remindProgram,
              selected: set,
              onTap: () => ref
                  .read(tvProgramRemindersProvider.notifier)
                  .toggle(channel: channel, program: n),
            ),
          ),
      ],
    );
  }
}

class _PanelButton extends StatelessWidget {
  const _PanelButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) => TvButton(
    icon: icon,
    label: label,
    onTap: onTap,
    primary: primary,
    escapeUpToSidebar: true,
    escapeToSidebar: primary,
  );
}

class _CategoryColumn extends StatelessWidget {
  const _CategoryColumn({
    required this.title,
    required this.labels,
    this.counts = const [],
    this.arrangeLabel,
    this.sortText,
    this.onArrange,
    required this.selected,
    this.selectedFocus,
    required this.onFocus,
    required this.onSelect,
    required this.onEnterChannels,
  });

  final String title;
  final List<String> labels;
  final List<int?> counts;
  final String? arrangeLabel;
  final String? sortText;
  final VoidCallback? onArrange;
  final int selected;
  /// Focus node of the open package's tile (Right from the channels).
  final FocusNode? selectedFocus;
  final ValueChanged<int> onFocus;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onEnterChannels;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 10, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              if (onArrange != null)
                FocusTile(
                  borderRadius: 16,
                  escapeToSidebar: false,
                  onTap: onArrange!,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    // Icon and word, as on LG and Movies / Series (client
                    // 9 Nov: an icon alone read as "Sort is missing").
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.swap_vert_rounded,
                          size: 20,
                          semanticLabel: arrangeLabel,
                          color: AppColors.cyan,
                        ),
                        if (sortText != null) ...[
                          const SizedBox(width: 4),
                          Text(
                            sortText!,
                            style: TextStyle(
                              color: AppColors.cyan,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: FocusTraversalGroup(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
              itemExtent: 46,
              itemCount: labels.length,
              itemBuilder: (_, i) {
                final active = i == selected;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Focus(
                    canRequestFocus: false,
                    skipTraversal: true,
                    onFocusChange: (f) {
                      if (f) onFocus(i);
                    },
                    onKeyEvent: (_, e) {
                      if (e is! KeyDownEvent) return KeyEventResult.ignored;
                      // Channels sit after the packages in reading order:
                      // left of them in Arabic, right of them in English.
                      final toChannels = Directionality.of(context) == TextDirection.rtl
                          ? LogicalKeyboardKey.arrowLeft
                          : LogicalKeyboardKey.arrowRight;
                      if (e.logicalKey != toChannels) {
                        return KeyEventResult.ignored;
                      }
                      onEnterChannels(i);
                      return KeyEventResult.handled;
                    },
                    child: FocusTile(
                      focusNode: i == selected ? selectedFocus : null,
                      autofocus: i == 0,
                      // Left leads to the channels, never to the menu.
                      escapeToSidebar: false,
                      borderRadius: 10,
                      onTap: () => onSelect(i),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        alignment: AlignmentDirectional.centerStart,
                        decoration: BoxDecoration(
                          color: active
                              ? AppColors.cyan.withValues(alpha: 0.16)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: active
                                ? AppColors.cyan.withValues(alpha: 0.35)
                                : Colors.transparent,
                          ),
                        ),
                        child: Row(
                          children: [
                            if (active) ...[
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: AppColors.cyan,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Expanded(
                              child: Text(
                                labels[i],
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: active
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  fontSize: 14,
                                  color: active
                                      ? AppColors.cyan
                                      : Colors.white,
                                ),
                              ),
                            ),
                            // Real channel count from the server, only when
                            // known (never 0 while loading).
                            if (i < counts.length && counts[i] != null)
                              Text(
                                '${counts[i]}',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _ChannelRow extends StatelessWidget {
  const _ChannelRow({
    this.focusNode,
    required this.number,
    required this.channel,
    required this.onFocus,
    required this.onTap,
    this.isLast = false,
    this.onRight,
  });

  /// Physical Right: to the open package (the packages sit right of the list).
  final VoidCallback? onRight;
  final FocusNode? focusNode;
  final int number;
  final MediaItem channel;
  final bool isLast;
  final VoidCallback onFocus;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sub = (channel.subtitle ?? '').trim();
    final badge = channel.badges.isNotEmpty ? channel.badges.first : null;
    final meta = ['CH $number', ?badge, if (sub.isNotEmpty) sub].join('  ·  ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (f) {
          if (f) onFocus();
        },
        child: FocusTile(
          focusNode: focusNode,
          borderRadius: 12,
          onTap: onTap,
          // Client 2 Nov: Down on the last channel stays there instead of
          // jumping into the categories / next panel.
          onKeyFirst: (e) {
            if (e is KeyUpEvent) return KeyEventResult.ignored;
            if (isLast && e.logicalKey == LogicalKeyboardKey.arrowDown) {
              return KeyEventResult.handled;
            }
            // Toward the packages: right in Arabic, left in English (LG order).
            final toPackages = Directionality.of(context) == TextDirection.rtl
                ? LogicalKeyboardKey.arrowRight
                : LogicalKeyboardKey.arrowLeft;
            if (onRight != null && e.logicalKey == toPackages) {
              if (e is KeyDownEvent) onRight!();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: ColoredBox(
                      color: AppColors.surfaceElevated,
                      child: RemoteImage(
                        url: channel.posterUrl ?? channel.backdropUrl,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        channel.displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.cyan,
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                if (channel.isLive || channel.kind == MediaKind.live) ...[
                  const TvPill('LIVE', tone: TvPillTone.live, compact: true),
                  const SizedBox(width: 8),
                ],
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: Colors.white.withValues(alpha: 0.35),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
