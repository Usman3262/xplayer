import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_log.dart';
import '../../core/ui_sound.dart';

/// Settings → Lab: replay splash animation, then pop back (does not re-boot app).
class SplashPreviewScreen extends ConsumerStatefulWidget {
  const SplashPreviewScreen({super.key});

  @override
  ConsumerState<SplashPreviewScreen> createState() =>
      _SplashPreviewScreenState();
}

class _SplashPreviewScreenState extends ConsumerState<SplashPreviewScreen> {
  Timer? _timer;
  bool _popped = false;

  @override
  void initState() {
    super.initState();
    AppLog.action('lab.splash_preview');
    _timer = Timer(const Duration(seconds: 5), _popBack);
  }

  void _popBack() {
    if (_popped || !mounted) return;
    _popped = true;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/settings');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // Match production splash sizing (client-adjusted).
    final markH = (size.shortestSide * 0.16).clamp(72.0, 110.0);
    final wordH = (size.shortestSide * 0.028).clamp(12.0, 18.0);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.15),
                radius: 1.1,
                colors: [
                  Color(0xFF0A1520),
                  Color(0xFF000000),
                ],
              ),
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: AppSplashBrand(
                markHeight: markH,
                wordmarkHeight: wordH,
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: IconButton(
                  tooltip: 'Close',
                  onPressed: () {
                    playUiTap(ref);
                    _popBack();
                  },
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
