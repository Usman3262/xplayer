import 'dart:async';

import 'package:data/data.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/tv_locale.dart';
import '../../widgets/focus_tile.dart';
import '../../widgets/tv_ui.dart';
import 'match_centre_adapters.dart';

/// Match centre (client: schedules, lineups, formations, substitutes,
/// events, statistics, timeline). Data: `/v1/sports/*` (server-side feed).

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _hm(DateTime? d) => d == null ? '' : matchClock(d);

String statusText(AppCopy copy, MatchFixture f) {
  if (f.status.short == 'HT') return copy.matchHalfTime;
  if (f.status.live) return "${f.status.elapsed ?? ''}'";
  if (f.status.finished) {
    return f.status.short == 'FT' ? copy.matchFullTime : f.status.short;
  }
  return _hm(f.kickoff);
}

/// Strip on the Sports tab: entry button + today's live / next matches.
class TvMatchCentreStrip extends ConsumerWidget {
  const TvMatchCentreStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = AppCopy.ofLanguage(ref.watch(tvLanguageProvider));
    final today = _ymd(DateTime.now());
    final day = ref.watch(matchDayProvider(today)).valueOrNull;
    final upcoming = [
      ...?day?.fixtures.where((f) => f.status.live),
      ...?day?.fixtures.where((f) => f.status.notStarted),
    ].take(8).toList();
    return SizedBox(
      height: 64,
      child: Row(
        children: [
          TvButton(
            label: copy.matchCentre,
            icon: Icons.sports_soccer_rounded,
            primary: true,
            escapeToSidebar: true,
            escapeUpToSidebar: true,
            onTap: () => context.push('/match-centre'),
          ),
          const SizedBox(width: 14),
          Expanded(
            // Cut the scrolled cards at the left edge only: they slid under
            // the "Matches & Lineups" button (TCL 21 Oct). The focus glow
            // above, below and on the right still shows.
            child: ClipRect(
              clipper: const _LeftEdgeClipper(),
              // Whole cards only (CEO 21 Oct: "…alatasaray" cut in half):
              // card width divides the strip, and scrolling snaps to cards.
              child: LayoutBuilder(
                builder: (context, box) {
                  const gap = 10.0;
                  // FocusTile draws a 2.5 px ring on each side, outside the card.
                  const ring = 2.5 * 2;
                  final n = ((box.maxWidth + gap) / 260).floor().clamp(1, 8);
                  final tileW = (box.maxWidth - gap * (n - 1)) / n;
                  final cardW = tileW - ring;
                  return _SnapToCards(
                    step: tileW + gap,
                    perPage: n,
                    builder: (controller, onCardFocus) => ListView.separated(
                      controller: controller,
                      scrollDirection: Axis.horizontal,
                      clipBehavior: Clip.none,
                      itemCount: upcoming.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 10),
                      itemBuilder: (_, i) {
                        final f = upcoming[i];
                        return Focus(
                          canRequestFocus: false,
                          skipTraversal: true,
                          onFocusChange: (has) {
                            if (has) onCardFocus(i);
                          },
                          child: FocusTile(
                            borderRadius: 12,
                            escapeUpToSidebar: true,
                            onTap: () => context.push('/match-centre/${f.id}'),
                            child: Container(
                              width: cardW,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.07),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  _Logo(f.home.logo, 22),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      '${f.home.nameFor(mpLang(copy))} – ${f.away.nameFor(mpLang(copy))}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  _StatusChip(
                                    copy: copy,
                                    fixture: f,
                                    compact: true,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Keeps a horizontal list on whole cards: the first visible card moves
/// only as far as needed to show the focused one, by whole card steps.
class _SnapToCards extends StatefulWidget {
  const _SnapToCards({
    required this.step,
    required this.perPage,
    required this.builder,
  });

  final double step;
  final int perPage;
  final Widget Function(
    ScrollController controller,
    void Function(int index) onCardFocus,
  )
  builder;

  @override
  State<_SnapToCards> createState() => _SnapToCardsState();
}

class _SnapToCardsState extends State<_SnapToCards> {
  final _controller = ScrollController();
  int _first = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onCardFocus(int i) {
    if (i < _first) _first = i;
    if (i >= _first + widget.perPage) _first = i - widget.perPage + 1;
    // After FocusTile's own "keep visible" scroll, so this one wins.
    Future<void>.delayed(const Duration(milliseconds: 40), () {
      if (!mounted || !_controller.hasClients) return;
      final pos = _controller.position;
      final target = (_first * widget.step)
          .clamp(pos.minScrollExtent, pos.maxScrollExtent)
          .toDouble();
      if ((target - pos.pixels).abs() < 0.5) return;
      _controller.animateTo(
        target,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(_controller, _onCardFocus);
}

/// Red pill text for a match in play ("LIVE 67'", "HT").
String? _livePill(AppCopy copy, MatchFixture f, [DateTime? now]) {
  if (f.status.short == 'HT') return copy.matchHalfTime;
  if (!f.status.live) return null;
  final at = now ?? DateTime.now();
  if (f.liveStale(at)) return copy.matchUpdating;
  final clock = f.liveClock(at);
  return '${copy.matchLive} ${clock ?? (f.status.elapsed == null ? '' : "${f.status.elapsed}'")}'
      .trim();
}

String _statusLine(AppCopy copy, MatchFixture f) {
  if (f.status.finished)
    return f.status.short == 'FT' ? copy.matchFullTime : f.status.short;
  if (f.status.live) return mpLiveStatus(copy, f);
  // Day of the kickoff on the sports (Riyadh) calendar, as the lists are;
  // the time itself is already in the score box (device time).
  final k = f.kickoff;
  if (k == null) return '';
  final days = matchTodayTomorrow();
  final d = matchSportsDay(k);
  if (d == days[0]) return copy.matchToday;
  if (d == days[1]) return copy.matchTomorrow;
  if (d == matchThreeDays()[0]) return copy.matchYesterday;
  return '${k.day}/${k.month}';
}

/// Live first, then upcoming by kickoff, then finished.
List<MatchFixture> _ordered(Iterable<MatchFixture> list) => sortMatches(list);

// LG size (client 5 Nov: match cards as on LG): 420 px on the 1920 px LG
// screen = 210 on the 960-point Android TV screen; contents scaled with it.
const _tvCardWidth = 210.0;
const _tvScale = 210.0 / 268.0;

Widget _tvCard(
  BuildContext context,
  AppCopy copy,
  MatchFixture f, {
  bool autofocus = false,
  bool escapeToSidebar = false,
  double width = _tvCardWidth,
  double scale = _tvScale,
}) {
  return FocusTile(
    borderRadius: 16,
    autofocus: autofocus,
    escapeToSidebar: escapeToSidebar,
    onTap: () => context.push('/match-centre/${f.id}'),
    child: McLiveTicker(
      active: f.status.live,
      builder: (context, now) => McMatchCard(
        width: width,
        scale: scale,
        competition: f.league.nameFor(mpLang(copy)),
        competitionLogo: f.league.logo,
        round: mpRound(copy, f.league.round),
        homeName: f.home.nameFor(mpLang(copy)),
        awayName: f.away.nameFor(mpLang(copy)),
        homeLogo: f.home.logo,
        awayLogo: f.away.logo,
        homeGoals: f.homeGoals,
        awayGoals: f.awayGoals,
        kickoff: _hm(f.kickoff),
        livePill: _livePill(copy, f, now),
        statusText: _statusLine(copy, f),
      ),
    ),
  );
}

/// Home "Today's & Tomorrow's Matches" rail (client 20 Oct: in the
/// sports slot, Continue Watching directly underneath).
class TvHomeMatchesRail extends ConsumerStatefulWidget {
  const TvHomeMatchesRail({super.key});

  @override
  ConsumerState<TvHomeMatchesRail> createState() => _TvHomeMatchesRailState();
}

class _TvHomeMatchesRailState extends ConsumerState<TvHomeMatchesRail> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Live scores on Home (TCL 21 Oct: the rail still said HT 2:0 while the
    // match was 3:0 in the 54th minute). Only while something is live.
    _tick = Timer.periodic(const Duration(seconds: 60), (_) {
      if (!mounted) return;
      final day = ref
          .read(matchDayProvider(matchTodayTomorrow()[0]))
          .valueOrNull;
      // Live, or past kickoff and not yet live here (client 24 Oct: a match
      // that starts must move ahead without a manual refresh).
      final now = DateTime.now();
      if (day != null && day.fixtures.any((f) => matchRank(f, now) == 0)) {
        ref.invalidate(matchDayProvider(matchTodayTomorrow()[0]));
      }
      setState(() {}); // re-order as kickoffs pass
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppCopy.ofLanguage(ref.watch(tvLanguageProvider));
    final days = matchTodayTomorrow();
    final today = ref.watch(matchDayProvider(days[0]));
    final tomorrow = ref.watch(matchDayProvider(days[1]));
    // One order over today + tomorrow: live, then nearest kickoff, then
    // finished (client 24 Oct).
    final items = sortMatches([
      ...?today.valueOrNull?.fixtures,
      ...?tomorrow.valueOrNull?.fixtures,
    ]);
    final live = items.any((e) => e.status.live);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 20, 8, 10),
                child: TvSectionTitle(
                  copy.matchTodayTomorrow,
                  accent: AppColors.magenta,
                  trailing: copy.viewAll,
                  onTap: () => context.push('/match-centre'),
                ),
              ),
            ),
            if (live)
              TechBadge(copy.matchLive, tone: BadgeTone.live, compact: true),
          ],
        ),
        // Client 2 Nov: smaller Today's Matches cards on Home.
        SizedBox(
          height: 156,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: items.length + 1,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, i) {
              if (i == items.length) {
                // Last tile: the full Match Centre.
                return FocusTile(
                  borderRadius: 16,
                  escapeToSidebar: items.isEmpty,
                  onTap: () => context.push('/match-centre'),
                  child: Container(
                    width: 170,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.sports_soccer_rounded,
                          color: AppColors.cyan,
                          size: 34,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          copy.matchCentre,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          items.isEmpty ? copy.matchNone : copy.matchSeeAll,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return _tvCard(context, copy, items[i], escapeToSidebar: i == 0, width: _tvCardWidth, scale: _tvScale);
            },
          ),
        ),
      ],
    );
  }
}

class TvMatchCentreScreen extends ConsumerStatefulWidget {
  const TvMatchCentreScreen({super.key});

  @override
  ConsumerState<TvMatchCentreScreen> createState() =>
      _TvMatchCentreScreenState();
}

class _TvMatchCentreScreenState extends ConsumerState<TvMatchCentreScreen> {
  // Client 20 Oct: Today and Tomorrow only.
  // Client 21 Oct: Yesterday, Today, Tomorrow (Today selected).
  final _days = matchThreeDays();
  int _sel = 1;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Live scores: the server refreshes every minute; follow it.
    _tick = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted && _sel == 1) ref.invalidate(matchDayProvider(_days[1]));
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppCopy.ofLanguage(ref.watch(tvLanguageProvider));
    final date = _days[_sel];
    final day = ref.watch(matchDayProvider(date));
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Padding(
        padding: const EdgeInsets.fromLTRB(48, 28, 48, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.sports_soccer_rounded,
                  color: AppColors.cyan,
                  size: 26,
                ),
                const SizedBox(width: 10),
                Text(
                  copy.matchCentre,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 14),
                Text(
                  copy.matchCentreHint,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                TvButton(
                  label: copy.matchYesterday,
                  selected: _sel == 0,
                  onTap: () => setState(() => _sel = 0),
                ),
                const SizedBox(width: 8),
                TvButton(
                  label: copy.matchToday,
                  selected: _sel == 1,
                  autofocus: true,
                  onTap: () => setState(() => _sel = 1),
                ),
                const SizedBox(width: 8),
                TvButton(
                  label: copy.matchTomorrow,
                  selected: _sel == 2,
                  onTap: () => setState(() => _sel = 2),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: day.when(
                loading: () =>
                    const Center(child: AppPlaybackLoading(logoHeight: 36)),
                // No Sports in the package (403, Usman 12 Nov): say so, no Retry.
                error: (e, _) => SportsApi.isNotInPackage(e)
                    ? _Message(copy.sportsNotInPackage)
                    : _Message(
                        copy.matchUnavailable,
                        onRetry: () => ref.invalidate(matchDayProvider(date)),
                      ),
                data: (d) {
                  if (d.fixtures.isEmpty) return _Message(copy.matchNone);
                  return LayoutBuilder(
                    builder: (context, box) {
                      // Three cards per row across the full width (cards used to
                      // stay 268 wide, leaving the right half of the screen empty).
                      const gap = 14.0;
                      final cardW = ((box.maxWidth - 8 - gap * 2) / 3)
                          .clamp(_tvCardWidth, 420.0)
                          .toDouble();
                      return ListView(
                        clipBehavior: Clip.hardEdge,
                        padding: const EdgeInsets.all(4),
                        children: [
                          if (d.stale) _StaleNote(copy: copy, at: d.fetchedAt),
                          for (final g in d.byLeague()) ...[
                            Padding(
                              padding: const EdgeInsets.only(
                                top: 10,
                                bottom: 10,
                              ),
                              child: Row(
                                children: [
                                  _LeagueLogo(g.key.logo, g.key.name, 26),
                                  const SizedBox(width: 10),
                                  Text(
                                    [
                                      g.key.nameFor(mpLang(copy)),
                                      if (g.key.country != null) g.key.country,
                                    ].join(' · '),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Wrap(
                              spacing: gap,
                              runSpacing: gap,
                              children: [
                                for (final f in _ordered(g.value))
                                  _tvCard(context, copy, f, width: cardW),
                              ],
                            ),
                            const SizedBox(height: 8),
                          ],
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TvMatchScreen extends ConsumerStatefulWidget {
  const TvMatchScreen({super.key, required this.id});
  final int id;

  @override
  ConsumerState<TvMatchScreen> createState() => _TvMatchScreenState();
}

/// Match page in the client's approved reference design (22 Oct), laid out
/// for 16:9: score card, Overview / Lineups / Events / Statistics / Match
/// Info pills; Lineups = team switch + angled pitch on the left, substitutes,
/// Match Events and Match Statistics on the right (all reachable by D-pad).
class _TvMatchScreenState extends ConsumerState<TvMatchScreen> {
  int? _team;
  // Client 23 Oct: the match page opens on Overview (was Lineups).
  int _tab = 0;

  /// Visible tab numbers (Lineups may be hidden); focus nodes follow the visible order.
  List<int> _ids = const [0, 1, 2, 3, 4];
  Timer? _tick;

  /// Tab pills move with Left / Right by index: directional search skipped
  /// from Events to the cards below and back (TCL 22 Oct: Left did nothing).
  final _tabNodes = List.generate(
    5,
    (i) => FocusNode(debugLabel: 'match-tab-$i'),
  );

  KeyEventResult _tabKey(int i, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    var step = 0;
    if (e.logicalKey == LogicalKeyboardKey.arrowLeft) step = rtl ? 1 : -1;
    if (e.logicalKey == LogicalKeyboardKey.arrowRight) step = rtl ? -1 : 1;
    if (step == 0) return KeyEventResult.ignored;
    final next = i + step;
    if (next >= 0 && next < _ids.length) _tabNodes[next].requestFocus();
    return KeyEventResult.handled;
  }

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 60), (_) {
      final m = ref.read(matchDetailProvider(widget.id)).valueOrNull;
      if (mounted && m != null && !m.fixture.status.finished) {
        ref.invalidate(matchDetailProvider(widget.id));
      }
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    for (final n in _tabNodes) {
      n.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppCopy.ofLanguage(ref.watch(tvLanguageProvider));
    final match = ref.watch(matchDetailProvider(widget.id));
    return Scaffold(
      backgroundColor: const Color(0xFF05080F),
      body: MpStadiumBackground(
        child: match.when(
          loading: () =>
              const Center(child: AppPlaybackLoading(logoHeight: 36)),
          error: (e, _) => SportsApi.isNotInPackage(e)
              ? _Message(copy.sportsNotInPackage)
              : _Message(
                  copy.matchUnavailable,
                  onRetry: () => ref.invalidate(matchDetailProvider(widget.id)),
                ),
          data: (m) => _page(copy, m),
        ),
      ),
    );
  }

  Widget _page(AppCopy copy, MatchDetail m) {
    final f = m.fixture;
    final team = _team ?? f.home.id;
    final lang = mpLang(copy);
    const s = 0.72;
    // Lineups can be switched off for everyone in the Control Panel (client 27 Oct).
    // Tab numbers stay the same; only the visible row (and its focus order) changes.
    // Follows the match answer itself (`lineupsHidden`, re-read every 60 s and
    // on every open), so the switch works at once, not only after a restart.
    final lineupsOn = !m.lineupsHidden;
    final ids = [0, if (lineupsOn) 1, 2, 3, 4];
    _ids = ids;
    if (!ids.contains(_tab)) _tab = 0;
    final allTabs = [
      copy.matchOverview,
      copy.matchLineups,
      copy.matchEvents,
      copy.matchStatistics,
      copy.matchStandingsTab,
    ];
    final tabs = [for (final i in ids) allTabs[i]];

    Widget focusCard(Widget child) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: FocusTile(borderRadius: 16, child: child),
    );
    Widget eventsCard({int? limit}) => MpCard(
      scale: s,
      title: copy.matchEventsTitle,
      child: MpEventsList(
        scale: s,
        events: mpEvents(copy, m, limit: limit),
        emptyText: copy.matchNoEvents,
      ),
    );
    Widget statsCard({bool all = false}) => MpCard(
      scale: s,
      title: copy.matchStatisticsTitle,
      child: MpStatsList(
        scale: s,
        stats: mpStats(copy, m, all: all),
        emptyText: copy.matchNoStats,
      ),
    );
    // Every card built up front so Down always finds the next one.
    Widget column(List<Widget> cards) => SingleChildScrollView(
      clipBehavior: Clip.hardEdge,
      padding: const EdgeInsets.all(4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final c in cards) focusCard(c)],
      ),
    );

    final Widget body;
    switch (_tab) {
      case 0:
        // Client 23 Oct: Overview = the complete match information.
        body = column([
          MpCard(
            scale: s,
            title: copy.matchInfoTitle,
            child: McLiveTicker(
              active: f.status.live,
              builder: (_, now) =>
                  MpInfoList(scale: 0.9, rows: mpInfo(copy, m, now: now)),
            ),
          ),
        ]);
      case 1:
        final l = m.lineupFor(team);
        body = Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 5,
              child: Column(
                children: [
                  MpTeamToggle(
                    scale: s,
                    homeName: f.home.nameFor(lang),
                    awayName: f.away.nameFor(lang),
                    homeLogo: f.home.logo,
                    awayLogo: f.away.logo,
                    homeSelected: team == f.home.id,
                    onSelect: (_) {},
                    itemBuilder: (home, side) => FocusTile(
                      borderRadius: 26,
                      onTap: () =>
                          setState(() => _team = home ? f.home.id : f.away.id),
                      child: side,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: l == null || l.startXI.isEmpty
                        ? Center(
                            child: Text(
                              copy.matchLineupsLater,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 15,
                              ),
                            ),
                          )
                        : Center(
                            child: MpPitch(
                              // Larger player photos (client 2 Nov #9); the
                              // pitch itself still fits via aspectRatio.
                              scale: 0.96,
                              aspectRatio: 1.3,
                              players: mpStarters(m, l),
                              formation: l.formation,
                            ),
                          ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 5,
              child: column([
                // Client 23 Oct: Lineups = pitch + substitutes only.
                if (l != null && l.substitutes.isNotEmpty)
                  MpSubstitutes(
                    scale: s,
                    title: copy.matchSubstitutes,
                    players: mpBench(m, l),
                  )
                else
                  MpCard(
                    scale: s,
                    title: copy.matchSubstitutes,
                    child: Text(
                      copy.matchLineupsLater,
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
              ]),
            ),
          ],
        );
      case 2:
        body = column([eventsCard()]);
      case 3:
        body = column([statsCard(all: true)]);
      default:
        // Client 23 Oct: "League Standings" tab, the full table only (it
        // shared the screen with Match Info).
        body = _TvStandings(copy: copy, m: m);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(36, 14, 36, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppLogo(height: 26),
              const SizedBox(width: 24),
              Expanded(
                child: McLiveTicker(
                  active: m.fixture.status.live,
                  builder: (_, now) =>
                      mpScoreCard(copy, m, scale: 0.62, now: now),
                ),
              ),
              const SizedBox(width: 24),
              SizedBox(
                width: 120,
                child: m.stale ? _StaleNote(copy: copy, at: m.fetchedAt) : null,
              ),
            ],
          ),
          const SizedBox(height: 10),
          MpTabs(
            scale: 0.8,
            labels: tabs,
            selected: ids.indexOf(_tab),
            onSelect: (_) {},
            itemBuilder: (i, pill) => FocusTile(
              borderRadius: 22,
              focusNode: _tabNodes[i],
              onKeyFirst: (e) => _tabKey(i, e),
              autofocus: i == 0, // Overview first (client 23 Oct)
              onTap: () => setState(() => _tab = ids[i]),
              child: pill,
            ),
          ),
          const SizedBox(height: 10),
          Expanded(child: body),
        ],
      ),
    );
  }
}

class _TvStandings extends ConsumerStatefulWidget {
  const _TvStandings({required this.copy, required this.m});
  final AppCopy copy;
  final MatchDetail m;

  @override
  ConsumerState<_TvStandings> createState() => _TvStandingsState();
}

/// Same table as the phone (client 23 Oct round 3 #6): Overall / Home /
/// Away, league logo + name, P W D L goals +/- points, zone colours. Rows
/// are focusable in blocks so the D-pad scrolls long tables.
class _TvStandingsState extends ConsumerState<_TvStandings> {
  StandingsView _view = StandingsView.overall;

  @override
  Widget build(BuildContext context) {
    final copy = widget.copy;
    final f = widget.m.fixture;
    final table = ref.watch(matchStandingsProvider(f.league.id));
    return table.when(
      loading: () => const Center(child: AppPlaybackLoading(logoHeight: 30)),
      error: (e, _) => SportsApi.isNotInPackage(e)
          ? _Message(copy.sportsNotInPackage)
          : _Message(
              copy.matchNoStandings,
              onRetry: () => ref.invalidate(matchStandingsProvider(f.league.id)),
            ),
      data: (t) {
        final groups = matchStandingGroups(t, f);
        final n = t.notice;
        // Plan without this season and no older table: say so (not just "not available").
        if (groups.isEmpty) {
          return _Message(
            n != null
                ? copy.matchStandingsNotInPlan(n.requestedSeason)
                : copy.matchNoStandings,
          );
        }
        final shown = n?.shownSeason ?? t.season;
        final lang = mpLang(copy);
        final zoneNames = {
          for (final g in groups)
            for (final r in g)
              if (r.description != null)
                r.description!: copy.matchZoneLabel(r.description!),
        };
        const block = 6;
        return ListView(
          clipBehavior: Clip.hardEdge,
          padding: const EdgeInsets.all(4),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: McSegmented(
                scale: 1.05,
                labels: copy.matchStandingsViews,
                selected: _view.index,
                onSelect: (i) =>
                    setState(() => _view = StandingsView.values[i]),
              ),
            ),
            for (final g in groups)
              ...() {
                final rows = matchStandingRows(g, f, lang, _view);
                final zones = mcZones(rows);
                return [
                  for (var i = 0; i < rows.length; i += block)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: FocusTile(
                        borderRadius: 16,
                        child: McStandingsTable(
                          scale: 1.05,
                          title: i == 0 ? t.league.nameFor(lang) : null,
                          titleLogo: t.league.logo ?? f.league.logo,
                          trailing: i == 0 && shown != null
                              ? AppCopy.seasonLabel(shown)
                              : null,
                          headers: copy.matchTableHeaders,
                          showHeader: i == 0,
                          showLegend: i + block >= rows.length,
                          zones: zones,
                          zoneNames: zoneNames,
                          rows: rows.sublist(
                            i,
                            (i + block).clamp(0, rows.length),
                          ),
                        ),
                      ),
                    ),
                ];
              }(),
            if (n != null && n.shownSeason != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10, left: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        copy.matchStandingsOlderSeason(
                          n.shownSeason!,
                          n.requestedSeason,
                        ),
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.copy,
    required this.fixture,
    this.compact = false,
  });
  final AppCopy copy;
  final MatchFixture fixture;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final live = fixture.status.live;
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (live) ...[
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: AppColors.live,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
        ],
        Text(
          statusText(copy, fixture),
          textDirection: TextDirection.ltr,
          style: TextStyle(
            fontSize: compact ? 11 : 14,
            fontWeight: FontWeight.w800,
            color: live ? AppColors.live : AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo(this.url, this.size);
  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: (url ?? '').isEmpty
        ? Icon(
            Icons.shield_outlined,
            size: size * 0.8,
            color: AppColors.textSecondary,
          )
        : RemoteImage(
            url: url,
            fit: BoxFit.contain,
            fallbackColors: const [Colors.transparent, Colors.transparent],
          ),
  );
}

class _StaleNote extends StatelessWidget {
  const _StaleNote({required this.copy, this.at});
  final AppCopy copy;
  final DateTime? at;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      copy.matchUpdated(_hm(at)),
      style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
    ),
  );
}

class _Message extends StatelessWidget {
  const _Message(this.text, {this.onRetry});
  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 15,
          ),
        ),
        if (onRetry != null) ...[
          const SizedBox(height: 14),
          TvButton(
            label: AppCopy.ofContext(context).retry,
            icon: Icons.refresh_rounded,
            autofocus: true,
            onTap: onRetry,
          ),
        ],
      ],
    ),
  );
}

/// Clips only the left side; leaves room for focus glow elsewhere.
class _LeftEdgeClipper extends CustomClipper<Rect> {
  const _LeftEdgeClipper();

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(0, -40, size.width + 40, size.height + 40);

  @override
  bool shouldReclip(_LeftEdgeClipper oldClipper) => false;
}

/// League logo on a light disc: many provider league logos are dark on
/// transparent (Ligue 1) and vanished on the dark circle. Missing URL → the
/// league's initial; a failed load shows a grey disc instead of nothing.
class _LeagueLogo extends StatelessWidget {
  const _LeagueLogo(this.url, this.name, this.size);
  final String? url;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        shape: BoxShape.circle,
      ),
      child: (url ?? '').isEmpty
          ? Center(
              child: Text(
                initial,
                style: TextStyle(
                  color: const Color(0xFF1C2433),
                  fontWeight: FontWeight.w900,
                  fontSize: size * 0.45,
                ),
              ),
            )
          : RemoteImage(
              url: url,
              fit: BoxFit.contain,
              fallbackColors: [AppColors.textSecondary, Color(0xFF6B7487)],
            ),
    );
  }
}
