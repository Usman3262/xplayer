import 'dart:async';

import 'package:data/data.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/session_controller.dart';
import 'match_centre_adapters.dart';

/// Match centre on the phone (client: schedules, lineups, formations,
/// substitutes, events, statistics, standings). Data: `/v1/sports/*`.
/// Layout follows the client's design of 20 Oct (see match_centre_ui.dart).

String _hm(DateTime? d) => d == null ? '' : matchClock(d);

AppCopy _copy(WidgetRef ref) =>
    AppCopy.ofLanguage(ref.watch(sessionProvider.select((s) => s.language)));

/// Red pill text for a match in play: "LIVE 67:12" (ticking), "HT".
String? _livePill(AppCopy copy, MatchFixture f, [DateTime? now]) {
  if (f.status.short == 'HT') return copy.matchHalfTime;
  if (!f.status.live) return null;
  final at = now ?? DateTime.now();
  if (f.liveStale(at)) return copy.matchUpdating;
  final clock = f.liveClock(at);
  return '${copy.matchLive} ${clock ?? (f.status.elapsed == null ? '' : "${f.status.elapsed}'")}'.trim();
}

String _statusLine(AppCopy copy, MatchFixture f) {
  if (f.status.finished) return f.status.short == 'FT' ? copy.matchFullTime : f.status.short;
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

Widget _card(BuildContext context, AppCopy copy, MatchFixture f, {double? width, double scale = 1}) {
  return GestureDetector(
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

/// Card at the top of the Sports tab.
class MatchCentreEntry extends ConsumerWidget {
  const MatchCentreEntry({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(matchCentreOnProvider).valueOrNull != true) return const SizedBox.shrink();
    final copy = _copy(ref);
    final day = ref.watch(matchDayProvider(matchTodayTomorrow().first)).valueOrNull;
    final live = day?.fixtures.where((f) => f.status.live).length ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Material(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.push('/match-centre'),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(Icons.sports_soccer_rounded, color: AppColors.cyan, size: 30),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(copy.matchCentre, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      const SizedBox(height: 2),
                      Text(copy.matchCentreHint,
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    ],
                  ),
                ),
                if (live > 0) ...[
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: AppColors.live, shape: BoxShape.circle)),
                  const SizedBox(width: 4),
                  Text('$live ${copy.matchLive}',
                      style: TextStyle(color: AppColors.live, fontWeight: FontWeight.w800, fontSize: 12)),
                  const SizedBox(width: 6),
                ],
                Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Home "Today's & Tomorrow's Matches" rail (client 20 Oct: in the
/// sports slot, Continue Watching directly underneath).
class HomeMatchesRail extends ConsumerStatefulWidget {
  const HomeMatchesRail({super.key, this.headerKey});
  final Key? headerKey;

  @override
  ConsumerState<HomeMatchesRail> createState() => _HomeMatchesRailState();
}

class _HomeMatchesRailState extends ConsumerState<HomeMatchesRail> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Live scores on Home: refresh every minute while a match is live.
    _tick = Timer.periodic(const Duration(seconds: 60), (_) {
      if (!mounted) return;
      final day = ref.read(matchDayProvider(matchTodayTomorrow()[0])).valueOrNull;
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
    final headerKey = widget.headerKey;
    final copy = _copy(ref);
    final days = matchTodayTomorrow();
    final today = ref.watch(matchDayProvider(days[0]));
    final tomorrow = ref.watch(matchDayProvider(days[1]));
    final loading = today.isLoading && !today.hasValue;
    // One order over today + tomorrow: live, then nearest kickoff, then
    // finished (client 24 Oct).
    final items = sortMatches([
      ...?today.valueOrNull?.fixtures,
      ...?tomorrow.valueOrNull?.fixtures,
    ]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KeyedSubtree(
          key: headerKey,
          child: SectionHeader(
            title: copy.matchTodayTomorrow,
            actionLabel: copy.seeAll,
            accent: AppColors.magenta,
            onAction: () => context.push('/match-centre'),
          ),
        ),
        SizedBox(
          height: 140,
          child: loading
              ? const Center(child: AppPlaybackLoading(logoHeight: 24))
              : items.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Center(
                        child: Text(
                          SportsApi.isNotInPackage(today.error)
                              ? copy.sportsNotInPackage
                              : today.hasError && tomorrow.hasError ? copy.matchUnavailable : copy.matchNone,
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      scrollDirection: Axis.horizontal,
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 12),
                      itemBuilder: (_, i) => _card(context, copy, items[i], width: 216, scale: 0.82),
                    ),
        ),
      ],
    );
  }
}

class MatchCentreScreen extends ConsumerStatefulWidget {
  const MatchCentreScreen({super.key});

  @override
  ConsumerState<MatchCentreScreen> createState() => _MatchCentreScreenState();
}

class _MatchCentreScreenState extends ConsumerState<MatchCentreScreen> {
  // Client 20 Oct: Today and Tomorrow only.
  // Client 21 Oct: Yesterday, Today, Tomorrow (Today selected).
  final _days = matchThreeDays();
  int _sel = 1;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
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
    final copy = _copy(ref);
    final date = _days[_sel];
    final day = ref.watch(matchDayProvider(date));
    return Scaffold(
      appBar: AppBar(title: Text(copy.matchCentre)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
            child: Row(
              children: [
                CategoryChip(label: copy.matchYesterday, selected: _sel == 0, onTap: () => setState(() => _sel = 0)),
                const SizedBox(width: 8),
                CategoryChip(label: copy.matchToday, selected: _sel == 1, onTap: () => setState(() => _sel = 1)),
                const SizedBox(width: 8),
                CategoryChip(label: copy.matchTomorrow, selected: _sel == 2, onTap: () => setState(() => _sel = 2)),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => ref.refresh(matchDayProvider(date).future),
              child: day.when(
                loading: () => const Center(child: AppPlaybackLoading(logoHeight: 32)),
                // No Sports in the package (403, Usman 12 Nov): say so, no Retry.
                error: (e, _) => SportsApi.isNotInPackage(e)
                    ? _Message(copy.sportsNotInPackage)
                    : _Message(copy.matchUnavailable, onRetry: () => ref.invalidate(matchDayProvider(date))),
                data: (d) {
                  if (d.fixtures.isEmpty) return _Message(copy.matchNone);
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    children: [
                      if (d.stale) _StaleNote(copy: copy, at: d.fetchedAt),
                      for (final g in d.byLeague()) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 12, bottom: 8),
                          child: Row(
                            children: [
                              McLogo(g.key.logo, 24),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  [g.key.nameFor(mpLang(copy)), if (g.key.country != null) g.key.country].join(' · '),
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                                ),
                              ),
                            ],
                          ),
                        ),
                        for (final f in _ordered(g.value))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _card(context, copy, f),
                          ),
                      ],
                    ],
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

class MatchScreen extends ConsumerStatefulWidget {
  const MatchScreen({super.key, required this.id});
  final int id;

  @override
  ConsumerState<MatchScreen> createState() => _MatchScreenState();
}

/// Match page in the client's approved reference design (22 Oct): stadium
/// background, score card, Overview / Lineups / Events / Statistics / Match
/// Info pills; Lineups = team switch, angled pitch with the formation,
/// substitutes, Match Events and Match Statistics cards.
class _MatchScreenState extends ConsumerState<MatchScreen> {
  Timer? _tick;
  int? _team;
  // Client 23 Oct: the match page opens on Overview (was Lineups).
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 60), (_) {
      final m = ref.read(matchDetailProvider(widget.id)).valueOrNull;
      if (mounted && m != null && !m.fixture.status.finished) ref.invalidate(matchDetailProvider(widget.id));
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final copy = _copy(ref);
    final match = ref.watch(matchDetailProvider(widget.id));
    return Scaffold(
      backgroundColor: const Color(0xFF05080F),
      body: MpStadiumBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: Icon(Directionality.of(context) == TextDirection.rtl
                          ? Icons.arrow_forward_ios_rounded
                          : Icons.arrow_back_ios_new_rounded),
                    ),
                    const Spacer(),
                    const AppLogo(height: 30),
                    const Spacer(),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              Expanded(
                child: match.when(
                  loading: () => const Center(child: AppPlaybackLoading(logoHeight: 32)),
                  error: (e, _) => SportsApi.isNotInPackage(e)
                      ? _Message(copy.sportsNotInPackage)
                      : _Message(copy.matchUnavailable, onRetry: () => ref.invalidate(matchDetailProvider(widget.id))),
                  data: (m) => _page(copy, m),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _page(AppCopy copy, MatchDetail m) {
    final f = m.fixture;
    final team = _team ?? f.home.id;
    final lang = mpLang(copy);
    // Lineups can be switched off for everyone in the Control Panel (client 27 Oct).
    // Tab numbers stay the same; only the visible row changes.
    // Follows the match answer itself (`lineupsHidden`, re-read every 60 s and
    // on every open), so the switch works at once, not only after a restart.
    final lineupsOn = !m.lineupsHidden;
    final ids = [0, if (lineupsOn) 1, 2, 3, 4];
    if (!ids.contains(_tab)) _tab = 0;
    final allTabs = [copy.matchOverview, copy.matchLineups, copy.matchEvents, copy.matchStatistics, copy.matchStandingsTab];
    final tabs = [for (final i in ids) allTabs[i]];
    Widget eventsCard({int? limit}) => MpCard(
          title: copy.matchEventsTitle,
          action: limit == null
              ? null
              : GestureDetector(
                  onTap: () => setState(() => _tab = 2),
                  child: Text('${copy.matchSeeAll} ›',
                      style: TextStyle(color: AppColors.cyan, fontWeight: FontWeight.w700)),
                ),
          footer: limit == null
              ? null
              : MpOutlineButton(label: copy.matchViewAllEvents, onTap: () => setState(() => _tab = 2)),
          child: MpEventsList(events: mpEvents(copy, m, limit: limit), emptyText: copy.matchNoEvents),
        );
    Widget statsCard({bool all = false}) => MpCard(
          title: copy.matchStatisticsTitle,
          footer: all ? null : MpOutlineButton(label: copy.matchViewAllStats, onTap: () => setState(() => _tab = 3)),
          child: MpStatsList(stats: mpStats(copy, m, all: all), emptyText: copy.matchNoStats),
        );

    final body = <Widget>[];
    switch (_tab) {
      case 0:
        // Client 23 Oct: Overview = the complete match information.
        body.add(MpCard(
          title: copy.matchInfoTitle,
          child: McLiveTicker(active: f.status.live, builder: (_, now) => MpInfoList(rows: mpInfo(copy, m, now: now))),
        ));
      case 1:
        final l = m.lineupFor(team);
        body.add(MpTeamToggle(
          homeName: f.home.nameFor(lang),
          awayName: f.away.nameFor(lang),
          homeLogo: f.home.logo,
          awayLogo: f.away.logo,
          homeSelected: team == f.home.id,
          onSelect: (home) => setState(() => _team = home ? f.home.id : f.away.id),
        ));
        body.add(const SizedBox(height: 12));
        if (l == null || l.startXI.isEmpty) {
          body.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Text(copy.matchLineupsLater,
                textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)),
          ));
        } else {
          body.add(MpPitch(players: mpStarters(m, l), formation: l.formation));
          if (l.substitutes.isNotEmpty) {
            body.addAll([const SizedBox(height: 12), MpSubstitutes(title: copy.matchSubstitutes, players: mpBench(m, l))]);
          }
        }
        // Client 23 Oct: Lineups = pitch + substitutes only.
      case 2:
        body.add(eventsCard());
      case 3:
        body.add(statsCard(all: true));
      default:
        // Client 23 Oct: "League Standings" tab, the full table only.
        body.add(_StandingsTab(copy: copy, m: m));
    }

    return RefreshIndicator(
      color: AppColors.cyan,
      onRefresh: () async => ref.invalidate(matchDetailProvider(widget.id)),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          McLiveTicker(active: m.fixture.status.live, builder: (_, now) => mpScoreCard(copy, m, now: now)),
          if (m.stale) Center(child: _StaleNote(copy: copy, at: m.fetchedAt)),
          const SizedBox(height: 14),
          MpTabs(labels: tabs, selected: ids.indexOf(_tab), onSelect: (i) => setState(() => _tab = ids[i])),
          const SizedBox(height: 14),
          ...body,
        ],
      ),
    );
  }
}

class _StandingsTab extends ConsumerStatefulWidget {
  const _StandingsTab({required this.copy, required this.m});
  final AppCopy copy;
  final MatchDetail m;

  @override
  ConsumerState<_StandingsTab> createState() => _StandingsTabState();
}

/// League table in the reference design (client 23 Oct round 3 #6):
/// Overall / Home / Away, league logo + name, P W D L goals +/- points and
/// the qualification / relegation colours.
class _StandingsTabState extends ConsumerState<_StandingsTab> {
  StandingsView _view = StandingsView.overall;

  @override
  Widget build(BuildContext context) {
    final copy = widget.copy;
    final f = widget.m.fixture;
    final table = ref.watch(matchStandingsProvider(f.league.id));
    Widget note(String text, {VoidCallback? retry}) => MpCard(
          title: copy.matchStandingsTab,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 8),
            child: Column(
              children: [
                Text(text, textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)),
                if (retry != null) TextButton(onPressed: retry, child: Text(copy.retry)),
              ],
            ),
          ),
        );
    return table.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: AppPlaybackLoading(logoHeight: 28)),
      ),
      error: (e, _) => SportsApi.isNotInPackage(e)
          ? note(copy.sportsNotInPackage)
          : note(copy.matchNoStandings, retry: () => ref.invalidate(matchStandingsProvider(f.league.id))),
      data: (t) {
        final groups = matchStandingGroups(t, f);
        final n = t.notice;
        // Plan without this season and no older table: say so (not just "not available").
        if (groups.isEmpty) {
          return note(n != null ? copy.matchStandingsNotInPlan(n.requestedSeason) : copy.matchNoStandings);
        }
        final shown = n?.shownSeason ?? t.season;
        final lang = mpLang(copy);
        final zoneNames = {
          for (final g in groups)
            for (final r in g)
              if (r.description != null) r.description!: copy.matchZoneLabel(r.description!),
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            McSegmented(
              labels: copy.matchStandingsViews,
              selected: _view.index,
              onSelect: (i) => setState(() => _view = StandingsView.values[i]),
            ),
            const SizedBox(height: 14),
            for (final g in groups) ...[
              McStandingsTable(
                title: t.league.nameFor(lang),
                titleLogo: t.league.logo ?? f.league.logo,
                trailing: shown == null ? null : AppCopy.seasonLabel(shown),
                headers: copy.matchTableHeaders,
                zoneNames: zoneNames,
                rows: matchStandingRows(g, f, lang, _view),
              ),
              const SizedBox(height: 12),
            ],
            if (n != null && n.shownSeason != null)
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded, size: 16, color: AppColors.textSecondary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(copy.matchStandingsOlderSeason(n.shownSeason!, n.requestedSeason),
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.35)),
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

class _StaleNote extends StatelessWidget {
  const _StaleNote({required this.copy, this.at});
  final AppCopy copy;
  final DateTime? at;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 4),
        child: Text(copy.matchUpdated(_hm(at)), style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
      );
}

class _Message extends StatelessWidget {
  const _Message(this.text, {this.onRetry});
  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => ListView(
        // Scrollable so pull-to-refresh works on empty days.
        children: [
          const SizedBox(height: 120),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)),
            ),
          ),
          if (onRetry != null)
            Center(
              child: TextButton(onPressed: onRetry, child: Text(AppCopy.ofContext(context).retry)),
            ),
        ],
      );
}
