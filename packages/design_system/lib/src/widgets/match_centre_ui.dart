import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'lineup_pitch.dart' show pitchColor;
import 'match_page_ui.dart' show goalBallBadge;
import 'remote_image.dart';

/// Match Centre building blocks, following the client's supplied design
/// ("APP 4K Sports Match Center & Lineup", 20 Oct): competition chip,
/// glowing score box, LIVE pill, single-team pitch with the top player
/// highlighted, bench strip, Key Match Events cards, Head-to-Head stats.
/// Plain inputs only, so the TV and phone apps share one look.
/// [scale] sizes everything (phone 1.0, TV about 1.25).

final _home = AppColors.cyan;
const _away = Color(0xFFFF4F9A);
const _card = Color(0xFF111826);
const _cardBorder = Color(0x1FFFFFFF);

class McChip extends StatelessWidget {
  McChip(this.text, {super.key, Color? color, this.scale = 1})
      : color = color ?? _home;
  final String text;
  final Color color;
  final double scale;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 3 * scale),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(4 * scale),
        ),
        child: Text(
          text.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: color, fontSize: 10.5 * scale, fontWeight: FontWeight.w800, letterSpacing: 0.6),
        ),
      );
}

class McLivePill extends StatelessWidget {
  const McLivePill(this.text, {super.key, this.scale = 1});
  final String text;
  final double scale;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 4 * scale),
        decoration: BoxDecoration(
          color: AppColors.live.withValues(alpha: 0.10),
          border: Border.all(color: AppColors.live.withValues(alpha: 0.7)),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 7 * scale, height: 7 * scale, decoration: BoxDecoration(color: AppColors.live, shape: BoxShape.circle)),
            SizedBox(width: 6 * scale),
            Text(text.toUpperCase(),
                style: TextStyle(color: AppColors.live, fontSize: 11 * scale, fontWeight: FontWeight.w900, letterSpacing: 0.6)),
          ],
        ),
      );
}

/// Rebuilds [builder] every second while [active] (live match clocks).
class McLiveTicker extends StatefulWidget {
  const McLiveTicker({super.key, required this.active, required this.builder});
  final bool active;
  final Widget Function(BuildContext context, DateTime now) builder;

  @override
  State<McLiveTicker> createState() => _McLiveTickerState();
}

class _McLiveTickerState extends State<McLiveTicker> {
  Timer? _t;

  void _sync() {
    _t?.cancel();
    _t = widget.active ? Timer.periodic(const Duration(seconds: 1), (_) => setState(() {})) : null;
  }

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(McLiveTicker old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) _sync();
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, DateTime.now());
}

class McLogo extends StatelessWidget {
  const McLogo(this.url, this.size, {super.key});
  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(size * 0.14),
        decoration: const BoxDecoration(color: Color(0xFF1C2433), shape: BoxShape.circle),
        child: (url ?? '').isEmpty
            ? Icon(Icons.shield_outlined, size: size * 0.5, color: AppColors.textSecondary)
            : RemoteImage(url: url, fit: BoxFit.contain, fallbackColors: const [Colors.transparent, Colors.transparent]),
      );
}

/// Glowing score box ("2 : 1") or the kickoff time.
class McScoreBox extends StatelessWidget {
  const McScoreBox({super.key, this.home, this.away, this.kickoff, this.scale = 1});
  final int? home;
  final int? away;
  final String? kickoff;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final hasScore = home != null && away != null;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 22 * scale, vertical: 8 * scale),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1220),
        borderRadius: BorderRadius.circular(16 * scale),
        border: Border.all(color: _home.withValues(alpha: 0.35)),
        boxShadow: [BoxShadow(color: _home.withValues(alpha: 0.18), blurRadius: 24 * scale)],
      ),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: hasScore
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$home', style: TextStyle(fontSize: 40 * scale, fontWeight: FontWeight.w900, height: 1)),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14 * scale),
                    child: Text(':', style: TextStyle(fontSize: 26 * scale, color: _home, fontWeight: FontWeight.w700)),
                  ),
                  Text('$away', style: TextStyle(fontSize: 40 * scale, fontWeight: FontWeight.w900, height: 1)),
                ],
              )
            : Text(kickoff ?? '', style: TextStyle(fontSize: 30 * scale, fontWeight: FontWeight.w900, height: 1.2)),
      ),
    );
  }
}

class McTeamHeader {
  const McTeamHeader({required this.name, this.logo, this.subtitle, this.tag});
  final String name;
  final String? logo;

  /// "MANAGER: CARLO ANCELOTTI • 4-3-1-2"
  final String? subtitle;

  /// Country code chip, e.g. "ESP".
  final String? tag;
}

/// Top of the match screen: competition + round, venue, live pill, both
/// teams with manager and formation, score box and a status line.
class McScoreHeader extends StatelessWidget {
  const McScoreHeader({
    super.key,
    required this.competition,
    required this.home,
    required this.away,
    this.round,
    this.venue,
    this.livePill,
    this.statusLine,
    this.homeGoals,
    this.awayGoals,
    this.kickoff,
    this.compact = false,
    this.scale = 1,
  });

  final String competition;
  final String? round;
  final String? venue;
  final String? livePill;
  final String? statusLine;
  final McTeamHeader home;
  final McTeamHeader away;
  final int? homeGoals;
  final int? awayGoals;
  final String? kickoff;

  /// Phone: teams stacked under the score instead of beside it.
  final bool compact;
  final double scale;

  Widget _team(McTeamHeader t, {required bool isHome}) {
    final logo = McLogo(t.logo, 54 * scale);
    final text = Column(
      crossAxisAlignment: compact ? CrossAxisAlignment.center : (isHome ? CrossAxisAlignment.start : CrossAxisAlignment.end),
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(t.name.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: compact ? TextAlign.center : null,
            style: TextStyle(fontSize: (compact ? 14 : 20) * scale, fontWeight: FontWeight.w900, letterSpacing: 0.2)),
        if ((t.subtitle ?? '').isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: 3 * scale),
            child: Text(t.subtitle!.toUpperCase(),
                maxLines: 2,
                textAlign: compact ? TextAlign.center : null,
                style: TextStyle(fontSize: 10 * scale, color: AppColors.textSecondary, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
          ),
      ],
    );
    if (compact) {
      return Expanded(child: Column(children: [logo, SizedBox(height: 8 * scale), text]));
    }
    return Expanded(
      child: Row(
        mainAxisAlignment: isHome ? MainAxisAlignment.start : MainAxisAlignment.end,
        children: isHome
            ? [logo, SizedBox(width: 14 * scale), Flexible(child: text)]
            : [Flexible(child: text), SizedBox(width: 14 * scale), logo],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      // Home on the left in every language, as in the design.
      textDirection: TextDirection.ltr,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // Competition keeps its full name; the round gives way first.
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: (compact ? 170 : 320) * scale),
                child: McChip(competition, scale: scale),
              ),
              SizedBox(width: 8 * scale),
              Expanded(
                child: Text((round ?? '').toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10.5 * scale, color: AppColors.textSecondary, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
              ),
              if (livePill != null) McLivePill(livePill!, scale: scale),
            ],
          ),
          if ((venue ?? '').isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: 6 * scale),
              child: Text(venue!.toUpperCase(),
                  style: TextStyle(fontSize: 10 * scale, color: AppColors.textSecondary, letterSpacing: 0.6)),
            ),
          SizedBox(height: 14 * scale),
          Row(
            crossAxisAlignment: compact ? CrossAxisAlignment.start : CrossAxisAlignment.center,
            children: [
              _team(home, isHome: true),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12 * scale),
                child: Column(
                  children: [
                    McScoreBox(home: homeGoals, away: awayGoals, kickoff: kickoff, scale: scale),
                    if ((statusLine ?? '').isNotEmpty)
                      Padding(
                        padding: EdgeInsets.only(top: 8 * scale),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(width: 6 * scale, height: 6 * scale, decoration: BoxDecoration(color: _home, shape: BoxShape.circle)),
                            SizedBox(width: 6 * scale),
                            Text(statusLine!.toUpperCase(),
                                style: TextStyle(fontSize: 10 * scale, color: AppColors.textSecondary, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              _team(away, isHome: false),
            ],
          ),
        ],
      ),
    );
  }
}

class McPlayer {
  const McPlayer({required this.name, this.number, this.grid, this.position, this.photo, this.card, this.subbedOff = false, this.goals = 0});
  final String name;
  final int? number;
  final String? grid;
  final String? position;
  final String? photo;

  /// 'yellow' | 'red' | null
  final String? card;
  final bool subbedOff;

  /// Goals scored in this match (ball marker above the player).
  final int goals;
}

/// One team on a full vertical pitch: goalkeeper at the bottom, attack at
/// the top (client design). The [highlight] player gets a glowing ring, a
/// name chip and a [highlightCaption] ("RATING 8.8 • 1 GOAL • 4 KEY PASSES").
class McTeamPitch extends StatelessWidget {
  const McTeamPitch({
    super.key,
    required this.players,
    this.kitColor,
    this.numberColor,
    this.highlight,
    this.highlightCaption,
    this.attackLabel,
    this.scale = 1,
  });

  final List<McPlayer> players;
  final String? kitColor;
  final String? numberColor;
  final String? highlight;
  final String? highlightCaption;
  final String? attackLabel;
  final double scale;

  static List<List<McPlayer>> _rows(List<McPlayer> players) {
    final byRow = <int, List<(int, McPlayer)>>{};
    var ok = players.isNotEmpty;
    for (final p in players) {
      final parts = (p.grid ?? '').split(':');
      final r = parts.length == 2 ? int.tryParse(parts[0]) : null;
      final c = parts.length == 2 ? int.tryParse(parts[1]) : null;
      if (r == null || c == null) {
        ok = false;
        break;
      }
      (byRow[r] ??= []).add((c, p));
    }
    if (ok) {
      final keys = byRow.keys.toList()..sort();
      return [
        for (final k in keys) [for (final e in (byRow[k]!..sort((a, b) => a.$1.compareTo(b.$1)))) e.$2],
      ];
    }
    const order = ['G', 'D', 'M', 'F'];
    final lines = <List<McPlayer>>[for (final _ in order) []];
    for (final p in players) {
      final i = order.indexOf((p.position ?? 'M').toUpperCase());
      lines[i < 0 ? 2 : i].add(p);
    }
    return [for (final l in lines) if (l.isNotEmpty) l];
  }

  @override
  Widget build(BuildContext context) {
    final kit = pitchColor(kitColor) ?? const Color(0xFFE5E7EB);
    final num = pitchColor(numberColor) ?? Colors.black;
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final h = c.maxHeight;
      final rows = _rows(players);
      // Also capped by height so 5 lines never overlap on a short pitch.
      final marker = math.min(math.min(46 * scale, w / 7.5), (h - 56 * scale) / (math.max(1, rows.length) * 1.35));
      final children = <Widget>[
        Positioned.fill(child: CustomPaint(painter: _VerticalPitchPainter())),
        if ((attackLabel ?? '').isNotEmpty)
          Positioned(
            right: 12 * scale,
            top: 8 * scale,
            child: Text(attackLabel!.toUpperCase(),
                style: TextStyle(color: Colors.white38, fontSize: 9 * scale, fontWeight: FontWeight.w800, letterSpacing: 1)),
          ),
      ];
      for (var r = 0; r < rows.length; r++) {
        final line = rows[r];
        // Row 0 (GK) at the bottom, the last row (attack) near the top,
        // leaving room for the top player's caption and the bottom names.
        final depth = rows.length == 1 ? 0.5 : r / (rows.length - 1);
        final topY = marker / 2 + 34 * scale;
        final botY = h - marker / 2 - 22 * scale;
        final y = botY - depth * math.max(0.0, botY - topY);
        for (var i = 0; i < line.length; i++) {
          final x = w * ((i + 0.5) / line.length);
          final p = line[i];
          final hi = highlight != null && p.name == highlight;
          final slotW = marker * 2.8;
          children.add(Positioned(
            left: x - slotW / 2,
            top: y - marker / 2 - (hi ? 4 * scale : 0),
            width: slotW,
            child: _PitchMarker(player: p, size: marker, kit: kit, number: num, highlighted: hi, scale: scale),
          ));
          if (hi && (highlightCaption ?? '').isNotEmpty) {
            // Own layer: wider than a name slot, kept inside the pitch.
            final capW = math.min(w - 16, 260 * scale);
            children.add(Positioned(
              left: (x - capW / 2).clamp(8.0, math.max(8.0, w - capW - 8)),
              top: y - marker / 2 - 4 * scale - 24 * scale,
              width: capW,
              child: Center(
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 3 * scale),
                  decoration: BoxDecoration(
                    color: _home,
                    borderRadius: BorderRadius.circular(99),
                    boxShadow: [BoxShadow(color: _home.withValues(alpha: 0.5), blurRadius: 10)],
                  ),
                  child: Text('★ ${highlightCaption!.toUpperCase()}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: const Color(0xFF041018), fontSize: 9.5 * scale, fontWeight: FontWeight.w900, letterSpacing: 0.3)),
                ),
              ),
            ));
          }
        }
      }
      return ClipRRect(borderRadius: BorderRadius.circular(16 * scale), child: Stack(clipBehavior: Clip.none, children: children));
    });
  }
}

class _PitchMarker extends StatelessWidget {
  const _PitchMarker({
    required this.player,
    required this.size,
    required this.kit,
    required this.number,
    required this.highlighted,
    required this.scale,
  });
  final McPlayer player;
  final double size;
  final Color kit;
  final Color number;
  final bool highlighted;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final parts = player.name.trim().split(RegExp(r'\s+'));
    final short = (parts.length > 1 ? parts.last : player.name).toUpperCase();
    final badge = math.max(15.0, size * 0.4);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: kit,
                  border: Border.all(color: highlighted ? _home : Colors.white70, width: highlighted ? 3 : 1.4),
                  boxShadow: [
                    BoxShadow(color: highlighted ? _home.withValues(alpha: 0.6) : const Color(0x66000000), blurRadius: highlighted ? 16 : 6),
                  ],
                ),
                child: ClipOval(
                  child: (player.photo ?? '').isNotEmpty
                      ? RemoteImage(url: player.photo, fit: BoxFit.cover, fallbackColors: [kit, kit])
                      : Center(child: Text('${player.number ?? ''}', style: TextStyle(color: number, fontWeight: FontWeight.w900, fontSize: size * 0.4))),
                ),
              ),
              if (player.number != null)
                Positioned(
                  right: -badge * 0.3,
                  top: -badge * 0.2,
                  child: Container(
                    width: badge,
                    height: badge,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: _home, shape: BoxShape.circle, border: Border.all(color: const Color(0xFF0B1220), width: 1.5)),
                    child: Text('${player.number}', style: TextStyle(color: const Color(0xFF041018), fontSize: badge * 0.52, fontWeight: FontWeight.w900)),
                  ),
                ),
              if (player.card != null)
                Positioned(
                  left: -2,
                  bottom: -2,
                  child: Container(
                    width: badge * 0.62,
                    height: badge * 0.8,
                    decoration: BoxDecoration(
                      color: player.card == 'red' ? const Color(0xFFE11D48) : const Color(0xFFFACC15),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              if (player.subbedOff)
                Positioned(
                  left: -badge * 0.25,
                  top: -badge * 0.2,
                  child: Container(
                    width: badge,
                    height: badge,
                    decoration: const BoxDecoration(color: _away, shape: BoxShape.circle),
                    child: Icon(Icons.swap_vert_rounded, size: badge * 0.7, color: Colors.white),
                  ),
                ),
              if (player.goals > 0)
                Positioned(
                  top: -badge * 0.95,
                  left: 0,
                  right: 0,
                  child: Center(child: goalBallBadge(player.goals, scale)),
                ),
            ],
          ),
        ),
        SizedBox(height: 4 * scale),
        Container(
          padding: highlighted ? EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 1 * scale) : EdgeInsets.zero,
          decoration: highlighted ? BoxDecoration(color: _home, borderRadius: BorderRadius.circular(4)) : null,
          child: Text(short,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: highlighted ? const Color(0xFF041018) : Colors.white,
                fontSize: 10 * scale,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.4,
                shadows: highlighted ? null : const [Shadow(color: Colors.black, blurRadius: 3)],
              )),
        ),
      ],
    );
  }
}

class _VerticalPitchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final rect = Offset.zero & s;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, -0.2),
          radius: 1.0,
          colors: [Color(0xFF1F6B3A), Color(0xFF0E3A22)],
        ).createShader(rect),
    );
    final stripe = Paint()..color = const Color(0x0CFFFFFF);
    for (var i = 0; i < 12; i += 2) {
      canvas.drawRect(Rect.fromLTWH(0, s.height * i / 12, s.width, s.height / 12), stripe);
    }
    final line = Paint()
      ..color = const Color(0x73FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final m = 10.0;
    final f = Rect.fromLTRB(m, m, s.width - m, s.height - m);
    canvas.drawRect(f, line);
    canvas.drawLine(Offset(f.left, f.center.dy), Offset(f.right, f.center.dy), line);
    canvas.drawCircle(f.center, math.min(f.width, f.height) * 0.13, line);
    final bw = f.width * 0.56;
    final bh = f.height * 0.13;
    final gw = f.width * 0.26;
    final gh = f.height * 0.05;
    canvas.drawRect(Rect.fromLTWH(f.center.dx - bw / 2, f.top, bw, bh), line);
    canvas.drawRect(Rect.fromLTWH(f.center.dx - bw / 2, f.bottom - bh, bw, bh), line);
    canvas.drawRect(Rect.fromLTWH(f.center.dx - gw / 2, f.top, gw, gh), line);
    canvas.drawRect(Rect.fromLTWH(f.center.dx - gw / 2, f.bottom - gh, gw, gh), line);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class McBenchPlayer {
  const McBenchPlayer({required this.name, this.number, this.photo, this.detail});
  final String name;
  final int? number;
  final String? photo;

  /// "MF • BENCH" / "FW • ON 58'"
  final String? detail;
}

/// "BENCH RESERVES (TEAM)" strip with substitutes.
class McBenchStrip extends StatelessWidget {
  const McBenchStrip({super.key, required this.title, required this.players, this.trailing, this.scale = 1});
  final String title;
  final String? trailing;
  final List<McBenchPlayer> players;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(Icons.event_seat_outlined, size: 14 * scale, color: _home),
            SizedBox(width: 6 * scale),
            Expanded(
              child: Text(title.toUpperCase(),
                  style: TextStyle(fontSize: 11 * scale, fontWeight: FontWeight.w900, letterSpacing: 0.6)),
            ),
            if (trailing != null)
              Text(trailing!.toUpperCase(), style: TextStyle(fontSize: 10 * scale, color: AppColors.textSecondary, letterSpacing: 0.5)),
          ],
        ),
        SizedBox(height: 8 * scale),
        SizedBox(
          height: 46 * scale,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: players.length,
            separatorBuilder: (_, _) => SizedBox(width: 8 * scale),
            itemBuilder: (_, i) {
              final p = players[i];
              return Container(
                padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 6 * scale),
                decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(10 * scale), border: Border.all(color: _cardBorder)),
                child: Row(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        CircleAvatar(
                          radius: 14 * scale,
                          backgroundColor: const Color(0xFF1C2433),
                          child: ClipOval(
                            child: (p.photo ?? '').isNotEmpty
                                ? RemoteImage(url: p.photo, width: 28 * scale, height: 28 * scale, fit: BoxFit.cover)
                                : Text('${p.number ?? ''}', style: TextStyle(fontSize: 11 * scale, fontWeight: FontWeight.w800)),
                          ),
                        ),
                        if (p.number != null)
                          Positioned(
                            right: -4,
                            top: -4,
                            child: Text('${p.number}', style: TextStyle(fontSize: 8.5 * scale, color: _home, fontWeight: FontWeight.w900)),
                          ),
                      ],
                    ),
                    SizedBox(width: 8 * scale),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.name.toUpperCase(), style: TextStyle(fontSize: 10.5 * scale, fontWeight: FontWeight.w900)),
                        if ((p.detail ?? '').isNotEmpty)
                          Text(p.detail!.toUpperCase(), style: TextStyle(fontSize: 9 * scale, color: AppColors.textSecondary)),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

enum McEventKind { goalHome, goalAway, yellow, red, sub, varCheck, other }

class McEvent {
  const McEvent({required this.kind, required this.title, this.subtitle, this.minute, this.home = true});
  final McEventKind kind;
  final String title;
  final String? subtitle;
  final String? minute;
  final bool home;
}

/// "Key Match Events" card (newest first, as in the design).
class McEventsCard extends StatelessWidget {
  const McEventsCard({super.key, required this.title, required this.events, this.badge, this.emptyText, this.scale = 1});
  final String title;
  final String? badge;
  final List<McEvent> events;
  final String? emptyText;
  final double scale;

  Widget _icon(McEvent e) {
    final s = 30 * scale;
    switch (e.kind) {
      case McEventKind.goalHome:
      case McEventKind.goalAway:
        final c = e.kind == McEventKind.goalHome ? _home : _away;
        return Container(width: s, height: s, decoration: BoxDecoration(color: c, shape: BoxShape.circle),
            child: Icon(Icons.sports_soccer_rounded, size: s * 0.6, color: const Color(0xFF041018)));
      case McEventKind.yellow:
      case McEventKind.red:
        return SizedBox(
          width: s,
          height: s,
          child: Center(
            child: Container(
              width: s * 0.62,
              height: s * 0.8,
              decoration: BoxDecoration(
                color: e.kind == McEventKind.red ? const Color(0xFFE11D48) : const Color(0xFFFACC15),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        );
      case McEventKind.sub:
        return Container(width: s, height: s, decoration: BoxDecoration(color: AppColors.match.withValues(alpha: 0.18), shape: BoxShape.circle),
            child: Icon(Icons.swap_vert_rounded, size: s * 0.6, color: AppColors.match));
      case McEventKind.varCheck:
        return Container(width: s, height: s, decoration: BoxDecoration(color: _home.withValues(alpha: 0.18), shape: BoxShape.circle),
            child: Icon(Icons.tv_rounded, size: s * 0.55, color: _home));
      case McEventKind.other:
        return Icon(Icons.info_outline_rounded, size: s * 0.7, color: AppColors.textSecondary);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(14 * scale),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16 * scale), border: Border.all(color: _cardBorder)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.schedule_rounded, size: 18 * scale, color: _home),
              SizedBox(width: 8 * scale),
              Expanded(child: Text(title, style: TextStyle(fontSize: 18 * scale, fontWeight: FontWeight.w800))),
              if (badge != null) McChip(badge!, color: AppColors.textSecondary, scale: scale),
            ],
          ),
          SizedBox(height: 10 * scale),
          if (events.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 10 * scale),
              child: Text(emptyText ?? '', style: TextStyle(color: AppColors.textSecondary, fontSize: 12 * scale)),
            ),
          for (final e in events)
            Container(
              margin: EdgeInsets.only(bottom: 8 * scale),
              padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 10 * scale),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.03), borderRadius: BorderRadius.circular(12 * scale)),
              child: Row(
                children: [
                  _icon(e),
                  SizedBox(width: 12 * scale),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 14 * scale, fontWeight: FontWeight.w800)),
                        if ((e.subtitle ?? '').isNotEmpty)
                          Text(e.subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11 * scale, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  if (e.minute != null)
                    Text(e.minute!, textDirection: TextDirection.ltr,
                        style: TextStyle(fontSize: 13 * scale, fontWeight: FontWeight.w900, color: e.home ? _home : _away)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class McStatBar {
  const McStatBar({required this.label, required this.home, required this.away, required this.homeValue, required this.awayValue});
  final String label;
  final String home;
  final String away;
  final double homeValue;
  final double awayValue;
}

class McStatBox {
  const McStatBox({required this.label, required this.value});
  final String label;
  final String value;
}

/// "Live Head-to-Head Stats": two-colour bars and three stat boxes.
class McHeadToHead extends StatelessWidget {
  const McHeadToHead({
    super.key,
    required this.title,
    required this.homeLabel,
    required this.awayLabel,
    required this.bars,
    required this.boxes,
    this.footnote,
    this.emptyText,
    this.scale = 1,
  });
  final String title;
  final String homeLabel;
  final String awayLabel;
  final List<McStatBar> bars;
  final List<McStatBox> boxes;
  final String? footnote;
  final String? emptyText;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(14 * scale),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16 * scale), border: Border.all(color: _cardBorder)),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(title, style: TextStyle(fontSize: 18 * scale, fontWeight: FontWeight.w800))),
                Text(homeLabel.toUpperCase(), style: TextStyle(color: _home, fontSize: 10 * scale, fontWeight: FontWeight.w900)),
                SizedBox(width: 12 * scale),
                Text(awayLabel.toUpperCase(), style: TextStyle(color: _away, fontSize: 10 * scale, fontWeight: FontWeight.w900)),
              ],
            ),
            SizedBox(height: 12 * scale),
            if (bars.isEmpty && boxes.isEmpty)
              Text(emptyText ?? '', style: TextStyle(color: AppColors.textSecondary, fontSize: 12 * scale)),
            for (final b in bars) ...[
              Row(
                children: [
                  Text(b.home, style: TextStyle(fontSize: 15 * scale, fontWeight: FontWeight.w900, color: _home)),
                  Expanded(
                    child: Text(b.label.toUpperCase(), textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 10 * scale, color: AppColors.textSecondary, letterSpacing: 0.6)),
                  ),
                  Text(b.away, style: TextStyle(fontSize: 15 * scale, fontWeight: FontWeight.w900, color: _away)),
                ],
              ),
              SizedBox(height: 5 * scale),
              _TwoToneBar(home: b.homeValue, away: b.awayValue, height: 7 * scale),
              SizedBox(height: 12 * scale),
            ],
            if (boxes.isNotEmpty)
              Row(
                children: [
                  for (var i = 0; i < boxes.length; i++) ...[
                    if (i > 0) SizedBox(width: 8 * scale),
                    Expanded(
                      child: Container(
                        padding: EdgeInsets.symmetric(vertical: 10 * scale, horizontal: 6 * scale),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.03), borderRadius: BorderRadius.circular(12 * scale)),
                        child: Column(
                          children: [
                            Text(boxes[i].label.toUpperCase(), textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 9.5 * scale, color: AppColors.textSecondary, letterSpacing: 0.5)),
                            SizedBox(height: 4 * scale),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(boxes[i].value, maxLines: 1, textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 15 * scale, fontWeight: FontWeight.w900)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            if ((footnote ?? '').isNotEmpty) ...[
              SizedBox(height: 12 * scale),
              Container(
                padding: EdgeInsets.all(10 * scale),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.03), borderRadius: BorderRadius.circular(12 * scale)),
                child: Row(
                  children: [
                    Icon(Icons.insights_rounded, size: 16 * scale, color: _home),
                    SizedBox(width: 8 * scale),
                    Expanded(child: Text(footnote!, style: TextStyle(fontSize: 12 * scale, color: AppColors.textSecondary))),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TwoToneBar extends StatelessWidget {
  const _TwoToneBar({required this.home, required this.away, required this.height});
  final double home;
  final double away;
  final double height;

  @override
  Widget build(BuildContext context) {
    final total = home + away;
    final f = total <= 0 ? 0.5 : home / total;
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: SizedBox(
        height: height,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: (f * 1000).round().clamp(1, 999), child: ColoredBox(color: _home)),
            const SizedBox(width: 3),
            Expanded(flex: ((1 - f) * 1000).round().clamp(1, 999), child: const ColoredBox(color: _away)),
          ],
        ),
      ),
    );
  }
}

/// Match card for Home and the Match Centre list (design language of the
/// supplied match screen: competition chip, crests, glowing score / time).
class McMatchCard extends StatelessWidget {
  const McMatchCard({
    super.key,
    required this.competition,
    required this.homeName,
    required this.awayName,
    this.competitionLogo,
    this.round,
    this.homeLogo,
    this.awayLogo,
    this.homeGoals,
    this.awayGoals,
    this.kickoff,
    this.livePill,
    this.statusText,
    this.width,
    this.focused = false,
    this.scale = 1,
  });

  final String competition;

  /// League logo beside its name (client 23 Oct round 3 #15).
  final String? competitionLogo;
  final String? round;
  final String homeName;
  final String awayName;
  final String? homeLogo;
  final String? awayLogo;
  final int? homeGoals;
  final int? awayGoals;
  final String? kickoff;

  /// "LIVE 67'" (red pill) when the match is in play.
  final String? livePill;

  /// "FT", "Tomorrow 21:00", …
  final String? statusText;
  final double? width;
  final bool focused;
  final double scale;

  @override
  Widget build(BuildContext context) {
    Widget team(String name, String? logo) => Expanded(
          child: Column(
            children: [
              McLogo(logo, 40 * scale),
              SizedBox(height: 6 * scale),
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12 * scale, fontWeight: FontWeight.w800)),
            ],
          ),
        );
    final hasScore = homeGoals != null && awayGoals != null;
    return Container(
      width: width,
      padding: EdgeInsets.all(12 * scale),
      decoration: BoxDecoration(
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF131C2C), Color(0xFF0C1220)]),
        borderRadius: BorderRadius.circular(16 * scale),
        border: Border.all(color: focused ? _home : _cardBorder, width: focused ? 2 : 1),
        boxShadow: focused ? [BoxShadow(color: _home.withValues(alpha: 0.35), blurRadius: 18 * scale)] : null,
      ),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                if (competitionLogo != null) ...[
                  McLogo(competitionLogo, 18 * scale),
                  SizedBox(width: 6 * scale),
                ],
                Expanded(child: Align(alignment: Alignment.centerLeft, child: McChip(competition, scale: scale))),
                if (livePill != null) ...[
                  SizedBox(width: 6 * scale),
                  McLivePill(livePill!, scale: scale * 0.85),
                ],
              ],
            ),
            if ((round ?? '').isNotEmpty)
              Padding(
                padding: EdgeInsets.only(top: 4 * scale),
                child: Text(round!.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 9.5 * scale, color: AppColors.textSecondary, letterSpacing: 0.5)),
              ),
            SizedBox(height: 10 * scale),
            Row(
              children: [
                team(homeName, homeLogo),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 6 * scale),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B1220),
                    borderRadius: BorderRadius.circular(10 * scale),
                    border: Border.all(color: _home.withValues(alpha: hasScore ? 0.35 : 0.15)),
                  ),
                  child: Text(
                    hasScore
                        ? (Directionality.of(context) == TextDirection.rtl
                            ? '$awayGoals : $homeGoals'
                            : '$homeGoals : $awayGoals')
                        : (kickoff ?? ''),
                    style: TextStyle(fontSize: (hasScore ? 20 : 15) * scale, fontWeight: FontWeight.w900),
                  ),
                ),
                team(awayName, awayLogo),
              ],
            ),
            if ((statusText ?? '').isNotEmpty)
              Padding(
                padding: EdgeInsets.only(top: 8 * scale),
                child: Text(statusText!.toUpperCase(), textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 10 * scale, color: AppColors.textSecondary, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
              ),
          ],
        ),
      ),
    );
  }
}

class McStandingRow {
  const McStandingRow({
    required this.rank,
    required this.team,
    required this.played,
    required this.goalDiff,
    required this.points,
    this.win = 0,
    this.draw = 0,
    this.lose = 0,
    this.goalsFor = 0,
    this.goalsAgainst = 0,
    this.logo,
    this.form,
    this.zone,
    this.highlight = false,
  });
  final int rank;
  final String team;
  final String? logo;
  final int played;
  final int win;
  final int draw;
  final int lose;
  final int goalsFor;
  final int goalsAgainst;
  final int goalDiff;
  final int points;
  final String? form;

  /// Qualification / relegation text from the provider (null = none).
  final String? zone;

  /// One of the two teams of the match.
  final bool highlight;
}

/// Colour of a qualification / relegation zone, from the provider's text
/// ("Promotion - AFC Champions League Elite", "Relegation", …).
Color? mcZoneColor(String? zone) {
  final z = (zone ?? '').toLowerCase();
  if (z.isEmpty) return null;
  if (z.contains('relegation')) {
    return z.contains('play') ? const Color(0xFFF97316) : const Color(0xFFEF4444);
  }
  if (z.contains('champions league') && !z.contains('qualif') && !z.contains('two')) {
    return const Color(0xFF3B82F6);
  }
  if (z.contains('europa') || z.contains('two') || z.contains('cup')) return const Color(0xFFF5B301);
  if (z.contains('conference') || z.contains('qualif') || z.contains('play')) return const Color(0xFF14B8A6);
  if (z.contains('promotion') || z.contains('champion')) return const Color(0xFF22C55E);
  return const Color(0xFF94A3B8);
}

/// Zone → colour for the legend, in table order.
Map<String, Color> mcZones(List<McStandingRow> rows) => {
      for (final r in rows)
        if (mcZoneColor(r.zone) != null) r.zone!: mcZoneColor(r.zone)!,
    };

/// League table in the reference design (client 23 Oct): league header,
/// then # · team (logo + name) · P · W · D · L · goals for:against · +/- ·
/// points, a coloured bar on the zone rows and the match's two teams
/// highlighted. Mirrors in right-to-left languages.
class McStandingsTable extends StatelessWidget {
  const McStandingsTable({
    super.key,
    required this.rows,
    required this.headers,
    this.title,
    this.titleLogo,
    this.trailing,
    this.zoneNames = const {},
    this.showHeader = true,
    this.showLegend = true,
    this.zones,
    this.scale = 1,
  });
  final List<McStandingRow> rows;

  /// TV splits a long table into focusable blocks: only the first shows the
  /// column header, only the last the zone legend ([zones] = whole table).
  final bool showHeader;
  final bool showLegend;
  final Map<String, Color>? zones;

  /// [#, Team, P, W, D, L, Goals, +/-, Pts, Form]
  final List<String> headers;

  /// League name and logo above the table.
  final String? title;
  final String? titleLogo;

  /// Shown at the end of the title row (e.g. "2024/25").
  final String? trailing;

  /// Translated zone names for the legend (provider text → label).
  final Map<String, String> zoneNames;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final head = TextStyle(fontSize: 11 * scale, color: AppColors.textSecondary, fontWeight: FontWeight.w700);
    final cell = TextStyle(fontSize: 13 * scale, fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()]);
    final zones = !showLegend ? const <String, Color>{} : (this.zones ?? mcZones(rows));
    return LayoutBuilder(builder: (context, c) {
      final narrow = c.maxWidth < 480 * scale;
      final numW = (narrow ? 22.0 : 34.0) * scale;
      final goalsW = (narrow ? 42.0 : 60.0) * scale;
      final ptsW = (narrow ? 28.0 : 40.0) * scale;
      // Last five results (W / D / L): own column on wide screens (TV),
      // small squares under the team name on phones.
      final formW = 5 * 15.0 * scale + 8 * scale;
      Widget form(String? f, double box) {
        final all = (f ?? '').split('').where((c) => 'WDL'.contains(c)).toList();
        final last = all.length <= 5 ? all : all.sublist(all.length - 5);
        return Row(
          mainAxisSize: MainAxisSize.min,
          textDirection: TextDirection.ltr,
          children: [
            for (final c in last)
              Container(
                width: box,
                height: box,
                margin: EdgeInsets.only(right: 2 * scale),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c == 'W' ? AppColors.match : c == 'L' ? const Color(0xFFE11D48) : const Color(0xFF94A3B8),
                  borderRadius: BorderRadius.circular(2.5 * scale),
                ),
                child: box >= 12 * scale
                    ? Text(c, style: TextStyle(fontSize: 8 * scale, fontWeight: FontWeight.w900, color: Colors.black))
                    : null,
              ),
          ],
        );
      }
      Widget num(String t, double w, {TextStyle? style}) => SizedBox(
            width: w,
            child: Text(t, textAlign: TextAlign.center, maxLines: 1, textDirection: TextDirection.ltr, style: style ?? cell),
          );
      Widget line(McStandingRow? r) {
        final style = r == null ? head : cell;
        final bar = r == null ? null : mcZoneColor(r.zone);
        return Container(
          height: (r == null ? 34 : 44) * scale,
          decoration: BoxDecoration(
            color: r?.highlight == true ? Colors.white.withValues(alpha: 0.07) : null,
            border: BorderDirectional(
              top: const BorderSide(color: _cardBorder),
              start: BorderSide(color: bar ?? Colors.transparent, width: 3 * scale),
            ),
          ),
          padding: EdgeInsetsDirectional.only(start: 7 * scale, end: 6 * scale),
          child: Row(
            children: [
              num(r == null ? headers[0] : '${r.rank}', 22 * scale, style: style),
              SizedBox(width: 4 * scale),
              if (r != null) ...[
                McLogo(r.logo, 22 * scale),
                SizedBox(width: 8 * scale),
              ],
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r == null ? headers[1] : r.team,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: r == null ? head : cell.copyWith(fontWeight: r.highlight ? FontWeight.w800 : FontWeight.w600),
                    ),
                    if (narrow && r != null && (r.form ?? '').isNotEmpty) ...[
                      SizedBox(height: 3 * scale),
                      form(r.form, 6 * scale),
                    ],
                  ],
                ),
              ),
              num(r == null ? headers[2] : '${r.played}', numW, style: style),
              num(r == null ? headers[3] : '${r.win}', numW, style: style),
              num(r == null ? headers[4] : '${r.draw}', numW, style: style),
              num(r == null ? headers[5] : '${r.lose}', numW, style: style),
              num(r == null ? headers[6] : '${r.goalsFor}:${r.goalsAgainst}', goalsW, style: style),
              num(r == null ? headers[7] : (r.goalDiff > 0 ? '+${r.goalDiff}' : '${r.goalDiff}'), numW + 4 * scale, style: style),
              num(r == null ? headers[8] : '${r.points}', ptsW,
                  style: r == null ? head : cell.copyWith(fontWeight: FontWeight.w900)),
              if (!narrow)
                SizedBox(
                  width: formW,
                  child: Center(
                    child: r == null
                        ? Text(headers.length > 9 ? headers[9] : '', style: head)
                        : form(r.form, 13 * scale),
                  ),
                ),
            ],
          ),
        );
      }

      return Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16 * scale), border: Border.all(color: _cardBorder)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null)
              Padding(
                padding: EdgeInsets.fromLTRB(14 * scale, 12 * scale, 14 * scale, 12 * scale),
                child: Row(
                  children: [
                    if (titleLogo != null) ...[
                      McLogo(titleLogo, 24 * scale),
                      SizedBox(width: 10 * scale),
                    ],
                    Expanded(
                      child: Text(title!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 15 * scale, fontWeight: FontWeight.w800)),
                    ),
                    if (trailing != null)
                      Text(trailing!, textDirection: TextDirection.ltr, style: head.copyWith(fontSize: 12 * scale)),
                  ],
                ),
              ),
            if (showHeader) line(null),
            for (final r in rows) line(r),
            if (zones.isNotEmpty)
              Container(
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: _cardBorder))),
                padding: EdgeInsets.fromLTRB(14 * scale, 10 * scale, 14 * scale, 12 * scale),
                child: Wrap(
                  spacing: 14 * scale,
                  runSpacing: 6 * scale,
                  children: [
                    for (final e in zones.entries)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(width: 10 * scale, height: 10 * scale, decoration: BoxDecoration(color: e.value, shape: BoxShape.circle)),
                          SizedBox(width: 6 * scale),
                          Flexible(
                            child: Text(zoneNames[e.key] ?? e.key,
                                style: TextStyle(fontSize: 11 * scale, color: AppColors.textSecondary)),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
          ],
        ),
      );
    });
  }
}

/// Pill switch (Overall / Home / Away) above the table.
class McSegmented extends StatelessWidget {
  const McSegmented({super.key, required this.labels, required this.selected, required this.onSelect, this.scale = 1});
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: EdgeInsets.all(3 * scale),
        decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(24 * scale), border: Border.all(color: _cardBorder)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < labels.length; i++)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 1.5 * scale),
                child: Material(
                  color: i == selected ? const Color(0xFF1E88FF) : Colors.transparent,
                  borderRadius: BorderRadius.circular(20 * scale),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20 * scale),
                    focusColor: Colors.white24,
                    onTap: () => onSelect(i),
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 22 * scale, vertical: 9 * scale),
                      child: Text(labels[i],
                          style: TextStyle(
                            fontSize: 14 * scale,
                            fontWeight: FontWeight.w700,
                            color: i == selected ? Colors.white : AppColors.textSecondary,
                          )),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
