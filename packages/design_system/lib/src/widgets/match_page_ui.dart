import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'app_logo.dart';
import 'remote_image.dart';

/// Match page in the client's approved reference design (22 Oct): stadium
/// background, score card (league, LIVE, minute, score), pill tabs, team
/// toggle, angled pitch with player photos and the formation badge,
/// substitutes strip, Match Events and Match Statistics cards. Plain inputs
/// only, so phone, iPhone and TV share one look; [scale] sizes everything.
/// Arabic: the parent's Directionality mirrors the layout.

const mpHome = Color(0xFFE8283C); // home team red (stat bars)
const mpAway = Color(0xFF1E88FF); // away team blue
const mpCard = Color(0xE60D1526);
const mpBorder = Color(0x2E5AA9FF);
final mpGlow = AppColors.cyan;

/// Dark navy stadium backdrop with floodlight glows.
class MpStadiumBackground extends StatelessWidget {
  const MpStadiumBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0B1630), Color(0xFF070C1A), Color(0xFF05080F)],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _FloodlightPainter()))),
            child,
          ],
        ),
      );
}

class _FloodlightPainter extends CustomPainter {
  const _FloodlightPainter();
  @override
  void paint(Canvas canvas, Size size) {
    void glow(Offset c, double r, Color color) {
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(colors: [color, color.withValues(alpha: 0)])
              .createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }

    glow(Offset(size.width * 0.05, 60), 160, const Color(0x40FFFFFF));
    glow(Offset(size.width * 0.95, 60), 160, const Color(0x40FFFFFF));
    glow(Offset(size.width * 0.5, 0), size.width * 0.6, const Color(0x2A1E88FF));
    glow(Offset(0, size.height * 0.35), 220, const Color(0x22E8283C));
    glow(Offset(size.width, size.height * 0.35), 220, const Color(0x221E88FF));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class MpTeamLogo extends StatelessWidget {
  const MpTeamLogo(this.url, this.size, {super.key});
  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: (url ?? '').isEmpty
            ? Icon(Icons.shield_rounded, size: size * 0.8, color: AppColors.textSecondary)
            : RemoteImage(url: url, fit: BoxFit.contain, fallbackColors: const [Colors.transparent, Colors.transparent]),
      );
}

/// League line + score card.
class MpScoreCard extends StatelessWidget {
  const MpScoreCard({
    super.key,
    required this.leagueName,
    this.leagueLogo,
    required this.homeName,
    required this.awayName,
    this.homeLogo,
    this.awayLogo,
    this.homeGoals,
    this.awayGoals,
    this.liveLabel,
    this.clock,
    this.statusText,
    this.scale = 1,
  });

  final String leagueName;
  final String? leagueLogo;
  final String homeName;
  final String awayName;
  final String? homeLogo;
  final String? awayLogo;
  final int? homeGoals;
  final int? awayGoals;

  /// "LIVE" / "مباشر" while in play; null otherwise.
  final String? liveLabel;

  /// Match minute ("67'") or kick-off time.
  final String? clock;

  /// FT / HT / date when not live.
  final String? statusText;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    // The score is drawn left-to-right, but in Arabic the home team sits on
    // the right, so its goals go on the right too.
    final score = homeGoals != null && awayGoals != null
        ? mpSideBySide(context, '$homeGoals', '$awayGoals')
        : 'vs';
    Widget team(String name, String? logo) => Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              MpTeamLogo(logo, 64 * s),
              SizedBox(height: 8 * s),
              Text(
                name,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 16 * s, fontWeight: FontWeight.w800, height: 1.15),
              ),
            ],
          ),
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if ((leagueLogo ?? '').isNotEmpty) ...[
              SizedBox(width: 22 * s, height: 22 * s, child: RemoteImage(url: leagueLogo, fit: BoxFit.contain)),
              SizedBox(width: 8 * s),
            ],
            Flexible(
              child: Text(
                leagueName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 15 * s, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        SizedBox(height: 10 * s),
        Container(
          padding: EdgeInsets.fromLTRB(12 * s, 14 * s, 12 * s, 14 * s),
          decoration: BoxDecoration(
            color: const Color(0xCC0B1222),
            borderRadius: BorderRadius.circular(18 * s),
            border: Border.all(color: mpBorder),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              team(homeName, homeLogo),
              SizedBox(
                width: 120 * s,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (liveLabel != null)
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 3 * s),
                        decoration: BoxDecoration(
                          color: const Color(0x33E8283C),
                          borderRadius: BorderRadius.circular(8 * s),
                          border: Border.all(color: mpHome),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 7 * s,
                              height: 7 * s,
                              decoration: const BoxDecoration(color: mpHome, shape: BoxShape.circle),
                            ),
                            SizedBox(width: 5 * s),
                            Text(liveLabel!, style: TextStyle(fontSize: 12 * s, fontWeight: FontWeight.w900)),
                          ],
                        ),
                      )
                    else if (statusText != null)
                      Text(statusText!,
                          style: TextStyle(fontSize: 12 * s, color: AppColors.textSecondary, fontWeight: FontWeight.w700)),
                    if (clock != null && liveLabel != null) ...[
                      SizedBox(height: 4 * s),
                      Text(clock!, style: TextStyle(fontSize: 14 * s, fontWeight: FontWeight.w700)),
                    ],
                    SizedBox(height: 2 * s),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(score,
                          style: TextStyle(fontSize: 40 * s, fontWeight: FontWeight.w900, height: 1.1, letterSpacing: 1)),
                    ),
                    if (clock != null && liveLabel == null)
                      Text(clock!, style: TextStyle(fontSize: 13 * s, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              team(awayName, awayLogo),
            ],
          ),
        ),
      ],
    );
  }
}

/// Pill tabs (Overview, Lineups, Events, Statistics, Match Info).
class MpTabs extends StatelessWidget {
  const MpTabs({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelect,
    this.scale = 1,
    this.itemBuilder,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;
  final double scale;

  /// TV: wrap each pill (focus). Default: a tap target.
  final Widget Function(int index, Widget pill)? itemBuilder;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Padding(
              padding: EdgeInsetsDirectional.only(end: 8 * s),
              child: () {
                final pill = MpPill(label: labels[i], selected: i == selected, scale: s);
                return itemBuilder != null
                    ? itemBuilder!(i, pill)
                    : GestureDetector(onTap: () => onSelect(i), child: pill);
              }(),
            ),
        ],
      ),
    );
  }
}

class MpPill extends StatelessWidget {
  const MpPill({super.key, required this.label, required this.selected, this.scale = 1, this.leading});
  final String label;
  final bool selected;
  final double scale;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.symmetric(horizontal: 18 * s, vertical: 11 * s),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFF0E2A4A) : const Color(0xCC0D1526),
        borderRadius: BorderRadius.circular(22 * s),
        border: Border.all(color: selected ? mpGlow : mpBorder, width: selected ? 1.6 : 1),
        boxShadow: selected ? [BoxShadow(color: mpGlow.withValues(alpha: 0.45), blurRadius: 14 * s)] : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[leading!, SizedBox(width: 8 * s)],
          Text(label, style: TextStyle(fontSize: 14 * s, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// Two-team switch: the selected team fills cyan.
class MpTeamToggle extends StatelessWidget {
  const MpTeamToggle({
    super.key,
    required this.homeName,
    required this.awayName,
    this.homeLogo,
    this.awayLogo,
    required this.homeSelected,
    required this.onSelect,
    this.scale = 1,
    this.itemBuilder,
  });

  final String homeName;
  final String awayName;
  final String? homeLogo;
  final String? awayLogo;
  final bool homeSelected;
  final ValueChanged<bool> onSelect;
  final double scale;
  final Widget Function(bool home, Widget side)? itemBuilder;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    Widget side(bool home) {
      final on = home == homeSelected;
      final w = Container(
        height: 52 * s,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? AppColors.cyan : Colors.transparent,
          borderRadius: BorderRadius.circular(26 * s),
          boxShadow: on ? [BoxShadow(color: mpGlow.withValues(alpha: 0.5), blurRadius: 16 * s)] : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                home ? homeName : awayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15 * s,
                  fontWeight: FontWeight.w800,
                  color: on ? const Color(0xFF04121F) : Colors.white,
                ),
              ),
            ),
            SizedBox(width: 8 * s),
            MpTeamLogo(home ? homeLogo : awayLogo, 26 * s),
          ],
        ),
      );
      return Expanded(
        child: itemBuilder != null ? itemBuilder!(home, w) : GestureDetector(onTap: () => onSelect(home), child: w),
      );
    }

    return Container(
      padding: EdgeInsets.all(4 * s),
      decoration: BoxDecoration(
        color: const Color(0xCC0D1526),
        borderRadius: BorderRadius.circular(30 * s),
        border: Border.all(color: mpBorder),
      ),
      child: Row(children: [side(true), SizedBox(width: 4 * s), side(false)]),
    );
  }
}

class MpPlayer {
  const MpPlayer({required this.name, this.number, this.photo, this.grid, this.position, this.card, this.subbedOff = false, this.goals = 0});
  final String name;
  final int? number;
  final String? photo;
  final String? grid;
  final String? position;
  final String? card;
  final bool subbedOff;

  /// Goals scored in this match (ball marker above the player).
  final int goals;
}

/// Lines of the starting XI from goalkeeper to forwards (grid "row:col"
/// first, position letters otherwise).
List<List<MpPlayer>> mpPitchRows(List<MpPlayer> players) {
  final byRow = <int, List<(int, MpPlayer)>>{};
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
  final lines = <List<MpPlayer>>[for (final _ in order) []];
  for (final p in players) {
    final i = order.indexOf((p.position ?? 'M').toUpperCase());
    lines[i < 0 ? 2 : i].add(p);
  }
  return [for (final l in lines) if (l.isNotEmpty) l];
}

/// Angled pitch: forwards at the top, goalkeeper at the bottom, formation
/// badge bottom-start, APP 4K mark in the centre circle.
class MpPitch extends StatelessWidget {
  const MpPitch({super.key, required this.players, this.formation, this.scale = 1, this.aspectRatio = 0.92});
  final List<MpPlayer> players;
  final String? formation;
  final double scale;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    final rows = mpPitchRows(players).reversed.toList();
    final s = scale;
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          final h = c.maxHeight;
          final markers = <Widget>[];
          for (var r = 0; r < rows.length; r++) {
            final row = rows[r];
            // Top line a little in from the far goal; GK near our goal.
            final y = rows.length == 1 ? 0.5 : 0.08 + 0.8 * r / (rows.length - 1);
            // Perspective: far lines narrower.
            final spread = 0.62 + 0.3 * y;
            for (var i = 0; i < row.length; i++) {
              final x = row.length == 1 ? 0.5 : 0.5 + spread * ((i / (row.length - 1)) - 0.5);
              markers.add(Positioned(
                left: x * w - 60 * s,
                top: y * h - 34 * s,
                width: 120 * s,
                child: _Marker(p: row[i], scale: s * (0.86 + 0.16 * y)),
              ));
            }
          }
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(child: CustomPaint(painter: _AngledPitchPainter())),
              Positioned(
                left: w / 2 - 44 * s,
                top: h * 0.5 - 30 * s,
                child: Opacity(opacity: 0.55, child: AppLogo(height: 60 * s, showWordmark: false)),
              ),
              ...markers,
              if ((formation ?? '').isNotEmpty)
                PositionedDirectional(
                  start: 10 * s,
                  bottom: 10 * s,
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 14 * s, vertical: 7 * s),
                    decoration: BoxDecoration(
                      color: const Color(0xE6070C18),
                      borderRadius: BorderRadius.circular(10 * s),
                      border: Border.all(color: mpBorder),
                    ),
                    child: Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(formation!.replaceAll('-', ' - '),
                          style: TextStyle(fontSize: 18 * s, fontWeight: FontWeight.w900)),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Marker extends StatelessWidget {
  const _Marker({required this.p, required this.scale});
  final MpPlayer p;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final d = 46 * s;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: d,
              height: d,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF1A2740),
                border: Border.all(color: const Color(0xFF9FD8FF), width: 1.6),
                boxShadow: [BoxShadow(color: mpGlow.withValues(alpha: 0.5), blurRadius: 10 * s)],
              ),
              clipBehavior: Clip.antiAlias,
              child: (p.photo ?? '').isEmpty
                  ? Icon(Icons.person_rounded, size: d * 0.7, color: Colors.white54)
                  : RemoteImage(url: p.photo, fit: BoxFit.cover),
            ),
            if (p.number != null)
              PositionedDirectional(
                start: -6 * s,
                bottom: -4 * s,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 5 * s, vertical: 1 * s),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A1220),
                    borderRadius: BorderRadius.circular(8 * s),
                  ),
                  child: Text('${p.number}', style: TextStyle(fontSize: 12 * s, fontWeight: FontWeight.w900)),
                ),
              ),
            if (p.card != null)
              PositionedDirectional(
                end: -4 * s,
                top: 0,
                child: Container(
                  width: 9 * s,
                  height: 13 * s,
                  decoration: BoxDecoration(
                    color: p.card == 'red' ? mpHome : const Color(0xFFFFD60A),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            if (p.subbedOff)
              PositionedDirectional(
                end: -6 * s,
                bottom: -2 * s,
                child: Icon(Icons.arrow_downward_rounded, size: 16 * s, color: mpHome),
              ),
            if (p.goals > 0)
              Positioned(
                top: -14 * s,
                left: 0,
                right: 0,
                child: Center(child: goalBallBadge(p.goals, s)),
              ),
          ],
        ),
        SizedBox(height: 3 * s),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 8 * s, vertical: 2 * s),
          decoration: BoxDecoration(color: const Color(0xD9070C18), borderRadius: BorderRadius.circular(8 * s)),
          child: Text(
            _short(p.name),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12 * s, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  static String _short(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length < 2 || name.length <= 12) return name;
    return '${parts.first[0]}. ${parts.sublist(1).join(' ')}';
  }
}

class _AngledPitchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    const inset = 0.13; // far side narrower
    final field = Path()
      ..moveTo(w * inset, 0)
      ..lineTo(w * (1 - inset), 0)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    // Striped grass.
    canvas.save();
    canvas.clipPath(field);
    const stripes = 10;
    for (var i = 0; i < stripes; i++) {
      canvas.drawRect(
        Rect.fromLTWH(0, h * i / stripes, w, h / stripes + 1),
        Paint()..color = i.isEven ? const Color(0xFF2E8B3A) : const Color(0xFF379A44),
      );
    }
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x33000000), Color(0x00000000), Color(0x22000000)],
        ).createShader(Offset.zero & size),
    );
    canvas.restore();

    final line = Paint()
      ..color = const Color(0xCCFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    // Map a point on a flat pitch (0..1, 0..1) into the trapezoid.
    Offset p(double x, double y) {
      final half = (1 - inset * 2 + inset * 2 * y) / 2;
      return Offset(w * (0.5 + (x - 0.5) * 2 * half), h * y);
    }

    Path poly(List<Offset> pts) {
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (final o in pts.skip(1)) {
        path.lineTo(o.dx, o.dy);
      }
      return path..close();
    }

    canvas.drawPath(field, line);
    canvas.drawLine(p(0, 0.5), p(1, 0.5), line);
    // Centre circle (ellipse in perspective).
    final c = p(0.5, 0.5);
    canvas.drawOval(Rect.fromCenter(center: c, width: w * 0.26, height: h * 0.17), line);
    canvas.drawCircle(c, 3, Paint()..color = Colors.white);
    // Penalty and goal areas, far and near.
    canvas.drawPath(poly([p(0.22, 0), p(0.78, 0), p(0.78, 0.15), p(0.22, 0.15)]), line);
    canvas.drawPath(poly([p(0.37, 0), p(0.63, 0), p(0.63, 0.06), p(0.37, 0.06)]), line);
    canvas.drawPath(poly([p(0.22, 1), p(0.78, 1), p(0.78, 0.84), p(0.22, 0.84)]), line);
    canvas.drawPath(poly([p(0.37, 1), p(0.63, 1), p(0.63, 0.94), p(0.37, 0.94)]), line);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Glass card with a title and an optional action / footer button.
class MpCard extends StatelessWidget {
  const MpCard({super.key, this.title, this.action, required this.child, this.footer, this.scale = 1});
  final String? title;
  final Widget? action;
  final Widget child;
  final Widget? footer;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    return Container(
      decoration: BoxDecoration(
        color: mpCard,
        borderRadius: BorderRadius.circular(16 * s),
        border: Border.all(color: mpBorder),
      ),
      padding: EdgeInsets.fromLTRB(14 * s, 12 * s, 14 * s, 12 * s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null)
            Padding(
              padding: EdgeInsets.only(bottom: 10 * s),
              child: Row(
                children: [
                  Expanded(child: Text(title!, style: TextStyle(fontSize: 18 * s, fontWeight: FontWeight.w800))),
                  ?action,
                ],
              ),
            ),
          child,
          if (footer != null) ...[SizedBox(height: 12 * s), footer!],
        ],
      ),
    );
  }
}

/// Outline button used under the cards ("View All Events").
class MpOutlineButton extends StatelessWidget {
  const MpOutlineButton({super.key, required this.label, this.onTap, this.scale = 1});
  final String label;
  final VoidCallback? onTap;
  final double scale;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 48 * scale,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12 * scale),
            border: Border.all(color: mpBorder),
            color: const Color(0x660A1220),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.chevron_left_rounded, size: 20 * scale, color: Colors.white70),
              SizedBox(width: 6 * scale),
              Text(label, style: TextStyle(fontSize: 15 * scale, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );
}

class MpBenchPlayer {
  const MpBenchPlayer({required this.name, this.number, this.photo, this.cameOn, this.goals = 0});
  final String name;
  final int? number;
  final String? photo;
  final String? cameOn;
  final int goals;
}

/// "^ Substitutes" strip of photo cards.
class MpSubstitutes extends StatelessWidget {
  const MpSubstitutes({super.key, required this.title, required this.players, this.scale = 1});
  final String title;
  final List<MpBenchPlayer> players;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    return Container(
      decoration: BoxDecoration(
        color: mpCard,
        borderRadius: BorderRadius.circular(16 * s),
        border: Border.all(color: mpBorder),
      ),
      padding: EdgeInsets.fromLTRB(10 * s, 10 * s, 10 * s, 12 * s),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.keyboard_arrow_up_rounded, size: 22 * s),
              SizedBox(width: 6 * s),
              Text(title, style: TextStyle(fontSize: 17 * s, fontWeight: FontWeight.w800)),
            ],
          ),
          SizedBox(height: 10 * s),
          // Client 23 / 24 Oct: substitutes in two or three rows, not one
          // scrolling line. Columns follow the width (phone 4-5, TV more).
          LayoutBuilder(builder: (context, c) {
            // At most three rows: enough columns for the bench, as many as
            // fit at a readable size (12 subs on a phone: 4 x 3).
            const minTile = 64.0;
            final gap = 8 * s;
            final fit = ((c.maxWidth + gap) / (minTile * s + gap)).floor().clamp(3, 8);
            final cols = ((players.length + 2) ~/ 3).clamp(3, fit);
            final tileW = (c.maxWidth - gap * (cols - 1)) / cols;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final p in players)
                  SizedBox(
                    width: tileW,
                    child: () {
                return Container(
                  height: 92 * s,
                  padding: EdgeInsets.all(6 * s),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111B2E),
                    borderRadius: BorderRadius.circular(10 * s),
                    border: Border.all(color: p.cameOn != null ? const Color(0xFF2ECC71) : mpBorder),
                  ),
                  child: Column(
                    children: [
                      Expanded(
                        child: Stack(
                          clipBehavior: Clip.none,
                          alignment: Alignment.center,
                          children: [
                            ClipOval(
                              child: SizedBox(
                                width: 44 * s,
                                height: 44 * s,
                                child: (p.photo ?? '').isEmpty
                                    ? const ColoredBox(color: Color(0xFF1A2740))
                                    : RemoteImage(url: p.photo, fit: BoxFit.cover),
                              ),
                            ),
                            if (p.goals > 0)
                              PositionedDirectional(top: -2 * s, end: 0, child: goalBallBadge(p.goals, s)),
                            if (p.number != null)
                              PositionedDirectional(
                                start: 2 * s,
                                bottom: 0,
                                child: Text('${p.number}',
                                    style: TextStyle(fontSize: 12 * s, fontWeight: FontWeight.w900)),
                              ),
                          ],
                        ),
                      ),
                      Text(
                        p.cameOn != null ? '${_last(p.name)} ${p.cameOn}' : _last(p.name),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5 * s, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                );
                    }(),
                  ),
              ],
            );
          }),
        ],
      ),
    );
  }

  static String _last(String n) {
    final parts = n.trim().split(RegExp(r'\s+'));
    return parts.length < 2 ? n : '${parts.first[0]}. ${parts.sublist(1).join(' ')}';
  }
}

enum MpEventKind { goal, yellow, red, sub, varCheck, other }

class MpEvent {
  const MpEvent({
    required this.minute,
    required this.kind,
    required this.label,
    required this.player,
    this.second,
    this.teamLogo,
    this.score,
  });
  final String minute;
  final MpEventKind kind;

  /// "Goal", "Yellow Card", "Substitution".
  final String label;
  final String player;

  /// Player coming on (substitution).
  final String? second;
  final String? teamLogo;
  final String? score;
}

class MpEventsList extends StatelessWidget {
  const MpEventsList({super.key, required this.events, required this.emptyText, this.scale = 1});
  final List<MpEvent> events;
  final String emptyText;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    if (events.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 16 * s),
        child: Text(emptyText, style: TextStyle(color: AppColors.textSecondary, fontSize: 14 * s)),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < events.length; i++) ...[
          if (i > 0) Divider(height: 1, color: Colors.white.withValues(alpha: 0.07)),
          _EventRow(e: events[i], scale: s),
        ],
      ],
    );
  }
}

/// "home - away" for left-to-right text, with the home value on the side
/// where the home team is drawn (the right in Arabic).
String mpSideBySide(BuildContext context, String home, String away) =>
    Directionality.of(context) == TextDirection.rtl ? '$away - $home' : '$home - $away';

/// A running score written "home - away" (e.g. "1 - 0"), ordered like the
/// score card.
String mpRunningScore(BuildContext context, String score) {
  final parts = score.split('-');
  if (parts.length != 2) return score;
  return mpSideBySide(context, parts[0].trim(), parts[1].trim());
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.e, required this.scale});
  final MpEvent e;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final icon = switch (e.kind) {
      MpEventKind.goal => Icon(Icons.sports_soccer_rounded, size: 24 * s, color: Colors.white),
      MpEventKind.yellow => _card(const Color(0xFFFFD60A), s),
      MpEventKind.red => _card(mpHome, s),
      MpEventKind.sub => Icon(Icons.sync_rounded, size: 24 * s, color: const Color(0xFF2ECC71)),
      MpEventKind.varCheck => Icon(Icons.tv_rounded, size: 22 * s, color: AppColors.cyan),
      MpEventKind.other => Icon(Icons.info_outline_rounded, size: 22 * s, color: Colors.white54),
    };
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8 * s),
      child: Row(
        children: [
          SizedBox(
            width: 52 * s,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Text(e.minute, style: TextStyle(fontSize: 15 * s, fontWeight: FontWeight.w800)),
            ),
          ),
          SizedBox(width: 30 * s, child: Center(child: icon)),
          SizedBox(width: 10 * s),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.label, style: TextStyle(fontSize: 13 * s, color: AppColors.textSecondary)),
                if (e.kind == MpEventKind.sub && e.second != null) ...[
                  _subLine(Icons.arrow_downward_rounded, mpHome, e.player, s),
                  _subLine(Icons.arrow_upward_rounded, const Color(0xFF2ECC71), e.second!, s),
                ] else
                  Text(e.player,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15 * s, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          if ((e.teamLogo ?? '').isNotEmpty) MpTeamLogo(e.teamLogo, 28 * s),
          SizedBox(
            width: 56 * s,
            child: e.score == null
                ? null
                : Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(mpRunningScore(context, e.score!),
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 15 * s, fontWeight: FontWeight.w800)),
                  ),
          ),
        ],
      ),
    );
  }

  static Widget _card(Color c, double s) => Container(
        width: 14 * s,
        height: 20 * s,
        decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3)),
      );

  static Widget _subLine(IconData i, Color c, String name, double s) => Row(
        children: [
          Icon(i, size: 14 * s, color: c),
          SizedBox(width: 4 * s),
          Expanded(
            child: Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14 * s, fontWeight: FontWeight.w700)),
          ),
        ],
      );
}

class MpStat {
  const MpStat({required this.label, required this.home, required this.away, this.homeValue, this.awayValue});
  final String label;
  final String home;
  final String away;
  final double? homeValue;
  final double? awayValue;
}

/// Home value | label over a red / blue bar | away value.
class MpStatsList extends StatelessWidget {
  const MpStatsList({super.key, required this.stats, required this.emptyText, this.scale = 1});
  final List<MpStat> stats;
  final String emptyText;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    if (stats.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 16 * s),
        child: Text(emptyText, style: TextStyle(color: AppColors.textSecondary, fontSize: 14 * s)),
      );
    }
    return Column(
      children: [
        for (final st in stats)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 6 * s),
            child: Row(
              children: [
                SizedBox(
                  width: 50 * s,
                  child: Text(st.home,
                      textAlign: TextAlign.start, style: TextStyle(fontSize: 14 * s, fontWeight: FontWeight.w700)),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(st.label, style: TextStyle(fontSize: 13 * s, color: Colors.white.withValues(alpha: 0.85))),
                      SizedBox(height: 5 * s),
                      _Bar(home: st.homeValue, away: st.awayValue, scale: s),
                    ],
                  ),
                ),
                SizedBox(
                  width: 50 * s,
                  child: Text(st.away,
                      textAlign: TextAlign.end, style: TextStyle(fontSize: 14 * s, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.home, required this.away, required this.scale});
  final double? home;
  final double? away;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final h = (home ?? 0).clamp(0, double.infinity).toDouble();
    final a = (away ?? 0).clamp(0, double.infinity).toDouble();
    final total = h + a;
    final hf = total <= 0 ? 0.5 : h / total;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 6 * scale,
        // Stretch: an empty ColoredBox is 0 px high under loose constraints
        // (the bars did not show on the Infinix, 22 Oct).
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: (hf * 1000).round().clamp(1, 999), child: const ColoredBox(color: mpHome)),
            SizedBox(width: 2 * scale),
            Expanded(flex: ((1 - hf) * 1000).round().clamp(1, 999), child: const ColoredBox(color: mpAway)),
          ],
        ),
      ),
    );
  }
}

/// Overview rows (client 23 Oct): icon · label · value, with an optional
/// logo before the value (the league logo beside the competition name).
class MpInfoList extends StatelessWidget {
  const MpInfoList({super.key, required this.rows, this.scale = 1});
  final List<(IconData, String, String, String?)> rows;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    return Column(
      children: [
        for (final r in rows)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 8 * s),
            child: Row(
              children: [
                Icon(r.$1, size: 20 * s, color: AppColors.cyan),
                SizedBox(width: 12 * s),
                Text(r.$2, style: TextStyle(fontSize: 14 * s, color: AppColors.textSecondary)),
                SizedBox(width: 16 * s),
                // Value (and logo) against the row's end edge.
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (r.$4 != null) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4 * s),
                          child: RemoteImage(url: r.$4, width: 20 * s, height: 20 * s, fit: BoxFit.contain),
                        ),
                        SizedBox(width: 8 * s),
                      ],
                      Flexible(
                        child: Text(r.$3,
                            textAlign: TextAlign.end,
                            style: TextStyle(fontSize: 14 * s, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Goal marker above a scorer (client 5 Nov, as on LG): a ball, "×2" for more.
Widget goalBallBadge(int goals, double s) => Container(
      padding: EdgeInsets.symmetric(horizontal: 4 * s, vertical: 1 * s),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10 * s),
        boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 4)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.sports_soccer, size: 13 * s, color: const Color(0xFF111111)),
          if (goals > 1)
            Text('×$goals', style: TextStyle(fontSize: 10 * s, fontWeight: FontWeight.w800, color: const Color(0xFF111111), height: 1.1)),
        ],
      ),
    );
