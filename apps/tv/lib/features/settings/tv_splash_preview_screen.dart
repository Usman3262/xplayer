import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

/// Settings → Lab: replay splash animation, then pop back (does not re-boot app).
class TvSplashPreviewScreen extends StatefulWidget {
  const TvSplashPreviewScreen({super.key});

  @override
  State<TvSplashPreviewScreen> createState() => _TvSplashPreviewScreenState();
}

class _TvSplashPreviewScreenState extends State<TvSplashPreviewScreen> {
  Timer? _timer;
  bool _popped = false;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 5), _popBack);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
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
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // Match production splash sizing (client-adjusted).
    final markH = (size.shortestSide * 0.14).clamp(88.0, 128.0);
    final wordH = (size.shortestSide * 0.025).clamp(14.0, 20.0);

    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.escape ||
            event.logicalKey == LogicalKeyboardKey.goBack ||
            event.logicalKey == LogicalKeyboardKey.backspace) {
          _popBack();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
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
                padding: const EdgeInsets.symmetric(horizontal: 48),
                child: AppSplashBrand(
                  markHeight: markH,
                  wordmarkHeight: wordH,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
