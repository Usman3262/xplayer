import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'remote_image.dart';

/// One starting player on the pitch.
class PitchPlayer {
  const PitchPlayer({
    required this.name,
    this.number,
    this.grid,
    this.position,
    this.photo,
  });
  final String name;
  final int? number;

  /// Provider grid "row:col": row 1 = goalkeeper, rising towards attack.
  final String? grid;

  /// G, D, M, F (used when the provider sends no grid).
  final String? position;
  final String? photo;
}

class PitchTeam {
  const PitchTeam({
    required this.players,
    this.kitColor,
    this.numberColor,
    this.keeperColor,
    this.keeperNumberColor,
  });
  final List<PitchPlayer> players;
  final Color? kitColor;
  final Color? numberColor;
  final Color? keeperColor;
  final Color? keeperNumberColor;
}

/// Parses "#rrggbb" / "rrggbb"; null when missing or invalid.
Color? pitchColor(String? hex) {
  final h = (hex ?? '').replaceAll('#', '').trim();
  if (h.length != 6) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}

/// Both starting XIs on one pitch (client: lineups + formations).
/// [horizontal] (TV): home on the left half, away on the right.
/// Vertical (phone): home on the bottom half, away on the top.
class LineupPitch extends StatelessWidget {
  const LineupPitch({
    super.key,
    required this.home,
    required this.away,
    this.horizontal = false,
    this.markerSize = 34,
    this.nameSize = 10,
  });

  final PitchTeam home;
  final PitchTeam away;
  final bool horizontal;
  final double markerSize;
  final double nameSize;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final h = c.maxHeight;
        final children = <Widget>[
          Positioned.fill(child: CustomPaint(painter: _PitchPainter(horizontal: horizontal))),
          ..._place(home, w, h, isHome: true),
          ..._place(away, w, h, isHome: false),
        ];
        return ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(children: children),
        );
      },
    );
  }

  List<Widget> _place(PitchTeam team, double w, double h, {required bool isHome}) {
    final rows = _rows(team.players);
    final rowCount = rows.length;
    final out = <Widget>[];
    final slotW = markerSize * 2.6;
    final slotH = markerSize + nameSize * 2.8;
    for (var r = 0; r < rowCount; r++) {
      final line = rows[r];
      for (var i = 0; i < line.length; i++) {
        // Depth from own goal (0) to halfway line (1); across the pitch 0..1.
        final depth = (r + 0.5) / rowCount;
        final across = (i + 0.5) / line.length;
        double x;
        double y;
        if (horizontal) {
          x = isHome ? depth * w / 2 : w - depth * w / 2;
          y = isHome ? across * h : (1 - across) * h;
        } else {
          y = isHome ? h - depth * h / 2 : depth * h / 2;
          x = isHome ? across * w : (1 - across) * w;
        }
        final p = line[i];
        final keeper = r == 0;
        out.add(
          Positioned(
            left: x - slotW / 2,
            top: y - slotH / 2,
            width: slotW,
            height: slotH,
            child: _Marker(
              player: p,
              size: markerSize,
              nameSize: nameSize,
              kit: (keeper ? team.keeperColor : team.kitColor) ??
                  (isHome ? const Color(0xFF1D4ED8) : const Color(0xFFEAB308)),
              number: (keeper ? team.keeperNumberColor : team.numberColor) ?? Colors.white,
            ),
          ),
        );
      }
    }
    return out;
  }

  /// Lines from the provider grid, else from G/D/M/F.
  static List<List<PitchPlayer>> _rows(List<PitchPlayer> players) {
    final byRow = <int, List<(int, PitchPlayer)>>{};
    var gridOk = players.isNotEmpty;
    for (final p in players) {
      final parts = (p.grid ?? '').split(':');
      final r = parts.length == 2 ? int.tryParse(parts[0]) : null;
      final c = parts.length == 2 ? int.tryParse(parts[1]) : null;
      if (r == null || c == null) {
        gridOk = false;
        break;
      }
      (byRow[r] ??= []).add((c, p));
    }
    if (gridOk) {
      final keys = byRow.keys.toList()..sort();
      return [
        for (final k in keys)
          [for (final e in (byRow[k]!..sort((a, b) => a.$1.compareTo(b.$1)))) e.$2],
      ];
    }
    const order = ['G', 'D', 'M', 'F'];
    final lines = <List<PitchPlayer>>[for (final _ in order) []];
    for (final p in players) {
      final i = order.indexOf((p.position ?? 'M').toUpperCase());
      lines[i < 0 ? 2 : i].add(p);
    }
    return [for (final l in lines) if (l.isNotEmpty) l];
  }
}

class _Marker extends StatelessWidget {
  const _Marker({
    required this.player,
    required this.size,
    required this.nameSize,
    required this.kit,
    required this.number,
  });
  final PitchPlayer player;
  final double size;
  final double nameSize;
  final Color kit;
  final Color number;

  @override
  Widget build(BuildContext context) {
    final parts = player.name.trim().split(RegExp(r'\s+'));
    final short = parts.length > 1 ? parts.last : player.name;
    final badge = math.max(14.0, size * 0.42);
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
                  border: Border.all(color: Colors.white, width: 1.6),
                  boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 6)],
                ),
                child: ClipOval(
                  child: (player.photo ?? '').isNotEmpty
                      ? RemoteImage(url: player.photo, fit: BoxFit.cover, fallbackColors: [kit, kit])
                      : Center(
                          child: Text(
                            '${player.number ?? ''}',
                            style: TextStyle(color: number, fontWeight: FontWeight.w800, fontSize: size * 0.42),
                          ),
                        ),
                ),
              ),
              if ((player.photo ?? '').isNotEmpty && player.number != null)
                Positioned(
                  right: -badge * 0.25,
                  bottom: -badge * 0.15,
                  child: Container(
                    width: badge,
                    height: badge,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: kit,
                      border: Border.all(color: Colors.white, width: 1),
                    ),
                    child: Text(
                      '${player.number}',
                      style: TextStyle(color: number, fontSize: badge * 0.55, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 3),
        Text(
          short,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: nameSize,
            fontWeight: FontWeight.w700,
            shadows: const [Shadow(color: Colors.black, blurRadius: 3)],
          ),
        ),
      ],
    );
  }
}

class _PitchPainter extends CustomPainter {
  const _PitchPainter({required this.horizontal});
  final bool horizontal;

  @override
  void paint(Canvas canvas, Size s) {
    final rect = Offset.zero & s;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF14532D), Color(0xFF166534), Color(0xFF14532D)],
        ).createShader(rect),
    );
    // Mowing stripes.
    final stripe = Paint()..color = const Color(0x0FFFFFFF);
    const n = 10;
    for (var i = 0; i < n; i += 2) {
      if (horizontal) {
        canvas.drawRect(Rect.fromLTWH(s.width * i / n, 0, s.width / n, s.height), stripe);
      } else {
        canvas.drawRect(Rect.fromLTWH(0, s.height * i / n, s.width, s.height / n), stripe);
      }
    }
    final line = Paint()
      ..color = const Color(0x8CFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final m = 6.0;
    final field = Rect.fromLTRB(m, m, s.width - m, s.height - m);
    canvas.drawRect(field, line);
    final c = field.center;
    final short = math.min(field.width, field.height);
    canvas.drawCircle(c, short * 0.13, line);
    canvas.drawCircle(c, 2.5, line..style = PaintingStyle.fill);
    line.style = PaintingStyle.stroke;
    if (horizontal) {
      canvas.drawLine(Offset(c.dx, field.top), Offset(c.dx, field.bottom), line);
      final bw = field.width * 0.13;
      final bh = field.height * 0.55;
      final gw = field.width * 0.05;
      final gh = field.height * 0.28;
      canvas.drawRect(Rect.fromLTWH(field.left, c.dy - bh / 2, bw, bh), line);
      canvas.drawRect(Rect.fromLTWH(field.right - bw, c.dy - bh / 2, bw, bh), line);
      canvas.drawRect(Rect.fromLTWH(field.left, c.dy - gh / 2, gw, gh), line);
      canvas.drawRect(Rect.fromLTWH(field.right - gw, c.dy - gh / 2, gw, gh), line);
    } else {
      canvas.drawLine(Offset(field.left, c.dy), Offset(field.right, c.dy), line);
      final bw = field.width * 0.55;
      final bh = field.height * 0.13;
      final gw = field.width * 0.28;
      final gh = field.height * 0.05;
      canvas.drawRect(Rect.fromLTWH(c.dx - bw / 2, field.top, bw, bh), line);
      canvas.drawRect(Rect.fromLTWH(c.dx - bw / 2, field.bottom - bh, bw, bh), line);
      canvas.drawRect(Rect.fromLTWH(c.dx - gw / 2, field.top, gw, gh), line);
      canvas.drawRect(Rect.fromLTWH(c.dx - gw / 2, field.bottom - gh, gw, gh), line);
    }
  }

  @override
  bool shouldRepaint(covariant _PitchPainter old) => old.horizontal != horizontal;
}
