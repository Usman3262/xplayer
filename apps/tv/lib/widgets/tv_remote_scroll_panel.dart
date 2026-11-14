import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A block of text to read that the remote can land on: Up / Down scroll it
/// (client 9 Nov: with nothing to focus, the rest stayed out of reach). Up at
/// the top leaves as usual. Down at the end stays, unless [downLeavesAtEnd]
/// (something focusable below, e.g. Speed Test's "Run again").
class TvRemoteScrollPanel extends StatefulWidget {
  const TvRemoteScrollPanel({
    super.key,
    required this.child,
    this.downLeavesAtEnd = false,
  });

  final Widget child;
  final bool downLeavesAtEnd;

  @override
  State<TvRemoteScrollPanel> createState() => _TvRemoteScrollPanelState();
}

class _TvRemoteScrollPanelState extends State<TvRemoteScrollPanel> {
  final _scroll = ScrollController();
  final _focus = FocusNode(debugLabel: 'remote-scroll-panel');
  bool _focused = false;

  @override
  void dispose() {
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent || !_scroll.hasClients) return KeyEventResult.ignored;
    final down = e.logicalKey == LogicalKeyboardKey.arrowDown;
    if (!down && e.logicalKey != LogicalKeyboardKey.arrowUp) {
      return KeyEventResult.ignored;
    }
    final p = _scroll.position;
    if (!down && p.pixels <= p.minScrollExtent) return KeyEventResult.ignored;
    if (down && widget.downLeavesAtEnd && p.pixels >= p.maxScrollExtent) {
      return KeyEventResult.ignored;
    }
    final target = (p.pixels + (down ? 120 : -120))
        .clamp(p.minScrollExtent, p.maxScrollExtent)
        .toDouble();
    _scroll.jumpTo(target);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      onFocusChange: (f) => setState(() => _focused = f),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _focused ? AppColors.cyan : Colors.transparent,
            width: 2,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: SingleChildScrollView(
            controller: _scroll,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
