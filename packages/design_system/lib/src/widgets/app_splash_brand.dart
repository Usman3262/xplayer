import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:vector_graphics/vector_graphics.dart';

import '../assets/app_assets.dart';
import '../theme/app_colors.dart';
import 'app_wordmark.dart';

/// Splash: raw SVG mark (transparent, no plate) + bolt on C→4→K + wordmark.
///
/// Performance: logo widget is built once; bolt ticker only repaints [CustomPaint].
class AppSplashBrand extends StatefulWidget {
  const AppSplashBrand({
    super.key,
    this.markAsset = AppAssets.logoMarkSvg,
    this.wordmarkAsset = AppAssets.wordmark,
    this.assetPackage = AppAssets.package,
    this.markHeight = 120,
    this.wordmarkHeight = 16,
    this.duration = const Duration(milliseconds: 3200),
    this.showWordmark = true,
    /// Playback / inline: mark + bolt only, loops forever.
    this.continuous = false,
    this.onFirstFrame,
    this.onComplete,
  });

  final String markAsset;
  final String wordmarkAsset;
  final String? assetPackage;
  final double markHeight;
  final double wordmarkHeight;
  final Duration duration;
  final bool showWordmark;
  final bool continuous;
  final VoidCallback? onFirstFrame;
  final VoidCallback? onComplete;

  /// SVG viewBox 900×500 — transparent, no black plate.
  static const markAspect = 900 / 500;

  @override
  State<AppSplashBrand> createState() => _AppSplashBrandState();
}

class _AppSplashBrandState extends State<AppSplashBrand>
    with TickerProviderStateMixin {
  late final AnimationController _master;
  late final AnimationController _bolt;
  late final AnimationController _markIn;
  late final AnimationController _wordIn;
  late final Animation<double> _markOpacity;
  late final Animation<double> _markScale;
  late final Animation<double> _wordOpacity;
  late final Animation<Offset> _wordSlide;

  late final Widget _logoImage;
  bool _first = false;
  bool _done = false;

  Widget _pngFallback() {
    return Image.asset(
      AppAssets.logoMark,
      package: widget.assetPackage,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      isAntiAlias: true,
      gaplessPlayback: true,
    );
  }

  Widget _buildMark() {
    final asset = widget.markAsset.toLowerCase();
    if (asset.endsWith('.vec')) {
      return SvgPicture(
        AssetBytesLoader(widget.markAsset, packageName: widget.assetPackage),
        fit: BoxFit.contain,
        placeholderBuilder: (_) => const SizedBox.expand(),
        errorBuilder: (_, _, _) => _pngFallback(),
      );
    }
    if (asset.endsWith('.svg')) {
      return SvgPicture.asset(
        widget.markAsset,
        package: widget.assetPackage,
        fit: BoxFit.contain,
        allowDrawingOutsideViewBox: false,
        placeholderBuilder: (_) => const SizedBox.expand(),
        errorBuilder: (_, _, _) => _pngFallback(),
      );
    }
    return Image.asset(
      widget.markAsset,
      package: widget.assetPackage,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      isAntiAlias: true,
      gaplessPlayback: true,
    );
  }

  @override
  void initState() {
    super.initState();

    _logoImage = _buildMark();

    _markIn = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _wordIn = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _master = AnimationController(vsync: this, duration: widget.duration);
    _bolt = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();

    _markOpacity = CurvedAnimation(parent: _markIn, curve: Curves.easeOut);
    _markScale = Tween<double>(begin: 0.94, end: 1).animate(
      CurvedAnimation(parent: _markIn, curve: Curves.easeOutCubic),
    );
    _wordOpacity = CurvedAnimation(parent: _wordIn, curve: Curves.easeOut);
    _wordSlide = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _wordIn, curve: Curves.easeOutCubic));

    if (widget.continuous) {
      _markIn.value = 1;
      _wordIn.value = 1;
    } else {
      _master.addStatusListener((s) {
        if (s == AnimationStatus.completed) _finish();
      });
      _markIn.forward();
      // Wordmark is visible immediately — no delayed morph that looks like
      // the APP text is changing mid-intro (client feedback).
      if (widget.showWordmark) {
        _wordIn.value = 1;
      }
      _master.forward();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => _signalFirst());
  }

  void _signalFirst() {
    if (_first) return;
    _first = true;
    widget.onFirstFrame?.call();
  }

  void _finish() {
    if (_done) return;
    _done = true;
    widget.onComplete?.call();
  }

  @override
  void dispose() {
    _master.dispose();
    _bolt.dispose();
    _markIn.dispose();
    _wordIn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Brand art stays LTR even when the app locale is RTL.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        width: double.infinity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FadeTransition(
              opacity: _markOpacity,
              child: ScaleTransition(
                scale: _markScale,
                child: SizedBox(
                  height: widget.markHeight,
                  child: AspectRatio(
                    aspectRatio: AppSplashBrand.markAspect,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(
                          color: Colors.transparent,
                          child: _logoImage,
                        ),
                        RepaintBoundary(
                          child: AnimatedBuilder(
                            animation: _bolt,
                            builder: (context, _) {
                              return CustomPaint(
                                painter: _LetterPathBoltPainter(
                                  progress: _bolt.value,
                                  power: 1,
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (widget.showWordmark && !widget.continuous)
              // Static wordmark under mark (splash stays centered hero).
              AppWordmark(height: widget.wordmarkHeight),
          ],
        ),
      ),
    );
  }
}

/// One bolt segment traveling a continuous C → 4 → K neon tube path (v4 style).
class _LetterPathBoltPainter extends CustomPainter {
  _LetterPathBoltPainter({required this.progress, required this.power});

  final double progress;
  final double power;

  static Path tubePath(Size size) {
    final w = size.width;
    final h = size.height;
    final p = Path();

    final c = Rect.fromLTWH(w * 0.05, h * 0.10, w * 0.48, h * 0.80);
    p.moveTo(c.center.dx + c.width * 0.32, c.top + c.height * 0.18);
    p.arcTo(c, -1.05, 4.55, false);

    p.lineTo(w * 0.52, h * 0.78);
    p.lineTo(w * 0.52, h * 0.22);
    p.lineTo(w * 0.40, h * 0.50);
    p.lineTo(w * 0.68, h * 0.50);
    p.lineTo(w * 0.94, h * 0.12);
    p.lineTo(w * 0.68, h * 0.50);
    p.lineTo(w * 0.96, h * 0.88);

    return p;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = tubePath(size);
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;

    final total = metrics.fold<double>(0, (s, m) => s + m.length);
    if (total < 2) return;

    final boltLen = total * 0.14;
    final head = total * (progress % 1.0);
    final tail = head - boltLen;

    final color = Color.lerp(
      AppColors.cyan,
      AppColors.magenta,
      progress,
    )!;

    var walked = 0.0;
    for (final metric in metrics) {
      final segStart = walked;
      final segEnd = walked + metric.length;

      void drawRange(double a, double b) {
        final start = a.clamp(segStart, segEnd) - segStart;
        final end = b.clamp(segStart, segEnd) - segStart;
        if (end <= start + 0.5) return;
        final extract = metric.extractPath(start, end);
        _strokeBolt(canvas, extract, color);
        final tip = metric.getTangentForOffset(end);
        if (tip != null) _tip(canvas, tip.position, color);
      }

      drawRange(tail, head);
      if (tail < 0) {
        drawRange(total + tail, total);
      }

      walked = segEnd;
    }
  }

  void _strokeBolt(Canvas canvas, Path extract, Color color) {
    canvas.drawPath(
      extract,
      Paint()
        ..color = color.withValues(alpha: 0.28 * power)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true,
    );
    canvas.drawPath(
      extract,
      Paint()
        ..color = color.withValues(alpha: 0.9 * power)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.2
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true,
    );
    canvas.drawPath(
      extract,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.98 * power)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true,
    );
  }

  void _tip(Canvas canvas, Offset pos, Color color) {
    canvas.drawCircle(
      pos,
      5,
      Paint()..color = color.withValues(alpha: 0.35 * power),
    );
    canvas.drawCircle(
      pos,
      3,
      Paint()..color = Colors.white.withValues(alpha: 0.95 * power),
    );
  }

  @override
  bool shouldRepaint(covariant _LetterPathBoltPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.power != power;
  }
}
