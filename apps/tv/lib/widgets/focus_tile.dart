import 'dart:async';

import 'package:data/data.dart' show TvPlatformProfile;
import 'package:design_system/design_system.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tv_shell_scope.dart';

/// D-pad focus wrapper with a pixel-stable cyan ring.
///
/// Border is drawn *inside* the layout bounds (no Transform.scale overflow),
/// so ListViews / grids never cut the left/right edges.
class FocusTile extends StatefulWidget {
  const FocusTile({
    super.key,
    required this.child,
    this.onTap,
    this.autofocus = false,
    this.borderRadius = 14,
    this.focusScale = 1.0,
    this.padding = EdgeInsets.zero,
    this.focusNode,
    this.escapeToSidebar = false,
    this.escapeUpToSidebar = false,
    this.borderWidth = 2.5,
    /// Top-nav tiles: Arrow Down should enter the page body, not skip around.
    this.downToContent = false,
    /// Home hero buttons: bring the banner fully on-screen before Up → menu.
    this.scrollToTopOnFocus = false,
    /// Drawn above [child] when focused (e.g. poster play glyph).
    this.focusedOverlay,
    this.ringColor,
    this.onKeyFirst,
    this.onLongSelect,
    this.glassFocus = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final bool autofocus;
  final double borderRadius;

  /// Keep at 1.0 for full-width rows. Use ~1.04 only on compact posters.
  final double focusScale;
  final EdgeInsets padding;
  final FocusNode? focusNode;

  /// First poster / chip in a horizontal row: Left returns to top nav.
  final bool escapeToSidebar;

  /// Only the topmost focusable row on a page: Up returns to top nav.
  /// Do **not** set this on lower category rails or Up will skip rows.
  final bool escapeUpToSidebar;
  final double borderWidth;
  final bool downToContent;
  final bool scrollToTopOnFocus;
  final Widget? focusedOverlay;

  /// Focus ring colour (default cyan). Cyan buttons use white: a cyan ring on
  /// a cyan Watch Now was nearly invisible on the TV.
  final Color? ringColor;

  /// Sees each key before the tile's own arrow handling. A wrapping [Focus]
  /// never did: the tile handled Up/Down first (client 18 Oct TV #1, the
  /// package-order dialog could not move a package).
  final KeyEventResult Function(KeyEvent event)? onKeyFirst;

  /// Holding OK (select / enter) for [_longSelect], then releasing it: this
  /// instead of [onTap]; a short OK still calls [onTap], on release (client
  /// 12 Nov: remove from Continue Watching with remotes that have no Red or
  /// Menu key). Both run on release: a dialog opened while OK is still held
  /// would get the key's repeats and press its own focused button. Null: OK
  /// opens on press as before.
  final VoidCallback? onLongSelect;

  /// Focus look for items that are already blue (client 12 Nov: Watch Now,
  /// All, the top tabs, Play/Pause): a white translucent "glass" layer, a
  /// bright white edge and glow, and a slight enlargement, so the focused
  /// one is clear even on a blue fill. Off: the usual cyan ring.
  final bool glassFocus;

  @override
  State<FocusTile> createState() => _FocusTileState();
}

class _FocusTileState extends State<FocusTile> {
  bool _focused = false;

  /// Focus node when the caller gives none: needed to move focus to the tile
  /// the LG Magic Remote pointer is over.
  FocusNode? _ownNode;
  FocusNode get _node =>
      widget.focusNode ?? (_ownNode ??= FocusNode(debugLabel: 'FocusTile'));

  /// Focus came from the pointer: do not scroll the page under the pointer.
  bool _focusFromPointer = false;

  @override
  void dispose() {
    _ownNode?.dispose();
    super.dispose();
  }

  /// LG webOS Magic Remote: the pointer moving over a tile focuses it, so OK
  /// and the highlight always act on the item under the pointer (client
  /// 26 Oct: "cannot reliably select items"). onHover fires only for real
  /// pointer movement, not when a page change puts a tile under the parked
  /// (hidden) pointer, so the remote's arrow keys keep their focus. Web only;
  /// Android TV has no pointer.
  void _onPointerHover(PointerHoverEvent e) {
    if (!kIsWeb || e.kind != PointerDeviceKind.mouse) return;
    final node = _node;
    if (node.hasFocus || !node.canRequestFocus) return;
    _focusFromPointer = true;
    node.requestFocus();
  }

  @override
  void initState() {
    super.initState();
    // A rebuilt tile that already holds focus (a package moved in the order
    // dialog) shows its ring at once.
    _focused = widget.focusNode?.hasFocus ?? false;
  }

  static const _longSelect = Duration(milliseconds: 650);
  DateTime? _selectDownAt;
  bool _longFired = false;

  static bool _isSelectKey(LogicalKeyboardKey k) =>
      k == LogicalKeyboardKey.select ||
      k == LogicalKeyboardKey.enter ||
      k == LogicalKeyboardKey.numpadEnter ||
      k == LogicalKeyboardKey.gameButtonA;

  KeyEventResult _onSelectHold(KeyEvent event) {
    if (event is KeyDownEvent) {
      _selectDownAt = DateTime.now();
      _longFired = false;
    } else if (event is KeyRepeatEvent) {
      final at = _selectDownAt;
      if (at != null && DateTime.now().difference(at) >= _longSelect) {
        _longFired = true;
      }
    } else if (event is KeyUpEvent) {
      final at = _selectDownAt;
      final long = _longFired ||
          (at != null && DateTime.now().difference(at) >= _longSelect);
      _selectDownAt = null;
      _longFired = false;
      if (at == null) return KeyEventResult.handled;
      if (long) {
        widget.onLongSelect?.call();
      } else {
        widget.onTap?.call();
      }
    }
    return KeyEventResult.handled;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final first = widget.onKeyFirst?.call(event);
    if (first == KeyEventResult.handled) return first!;
    if (widget.onLongSelect != null && _isSelectKey(event.logicalKey)) {
      return _onSelectHold(event);
    }
    // Holding a key sends repeat events: they get the same handling as a
    // press. They were ignored here, so Flutter's default arrow traversal
    // took them and a held Left / Right jumped to another row (client 26 Oct).
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final shell = TvShellScope.maybeOf(context);
    final primary = FocusManager.instance.primaryFocus;

    if (key == LogicalKeyboardKey.arrowDown) {
      if (widget.downToContent) {
        shell?.focusContent();
        return KeyEventResult.handled;
      }
      tvMoveFocus(primary, TraversalDirection.down);
      // Always consume so focus cannot leak into the top-nav FocusScope.
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowUp) {
      // Hero / banner controls: if the page is still scrolled, pin to top
      // first so Up does not skip the hero and land on the top menu.
      if (widget.scrollToTopOnFocus) {
        ScrollPosition? pos;
        for (var s = Scrollable.maybeOf(context);
            s != null;
            s = Scrollable.maybeOf(s.context)) {
          if (s.position.axis == Axis.vertical) {
            pos = s.position;
            break;
          }
        }
        if (pos != null && pos.pixels > pos.minScrollExtent + 1) {
          unawaited(_tvScrollTo(pos, pos.minScrollExtent, 160));
          return KeyEventResult.handled;
        }
      }
      // Top row of a page: nothing above but the menu, so go straight there
      // (directional search sometimes "succeeded" without moving, and Up
      // looked dead on My List / Details in the Home banner).
      if (widget.escapeUpToSidebar && shell != null) {
        shell.focusSidebar();
        return KeyEventResult.handled;
      }
      final moved =
          tvMoveFocus(primary, TraversalDirection.up);
      if (moved) {
        // The search can report a move and leave focus where it was (17 Oct:
        // Up on the Home banner's Watch Now did nothing). Focus changes in a
        // microtask; if it is still here, go to the top menu.
        final ctx = context;
        scheduleMicrotask(() {
          if (FocusManager.instance.primaryFocus == primary &&
              ctx.mounted) {
            tvEscapeUpFrom(ctx, shell?.focusSidebar);
          }
        });
        return KeyEventResult.handled;
      }
      // Nothing focusable above. If the page is scrolled down, the row above
      // may just not be built yet: scroll up and try again. At the top of the
      // page, go to the top menu (before, Up was swallowed on most pages and
      // the menu could not be reached from the content).
      tvEscapeUpFrom(context, shell?.focusSidebar);
      return KeyEventResult.handled;
    }

    // Left / Right inside a horizontal row stay in that row (client 21 Oct:
    // Left on the first item went down, Right on the last went up). At the
    // edge the focus stays where it is. Tiles outside rows (side-by-side
    // panels, grids) keep the normal directional move.
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      final row = _horizontalScrollable(context);
      if (row != null && primary != null) {
        final from = primary.rect;
        // At the start / end of the row there is nothing further that way:
        // stay put. Trying the move first let the search pick a card in the
        // next row; the page scrolled there before focus was pulled back, so
        // Left on the first card looked like a move down (client 24 Oct TV #3).
        if (_atRowEdge(row, from, left: key == LogicalKeyboardKey.arrowLeft)) {
          // A control beside the row on the same line is still reachable
          // (Sports: first match card -> "Matches & Lineups").
          _focusSameLine(primary, from, left: key == LogicalKeyboardKey.arrowLeft);
          return KeyEventResult.handled;
        }
        // Move to the next card of this row only. The general directional
        // search could pick a card in another row when the next card was
        // not built yet (holding a key runs ahead of the row): the page
        // scrolled to that row before focus was pulled back (client 26 Oct,
        // TCL: holding Right on Top Movies jumped up to Continue Watching).
        final left = key == LogicalKeyboardKey.arrowLeft;
        final next = _nextInRow(row, primary, from, left: left);
        if (next != null) {
          next.requestFocus();
        } else if (!_scrollRowThenFocus(row, primary, from, left: left)) {
          // Nothing more in the row: a control beside it on the same line.
          _focusSameLine(primary, from, left: left);
        }
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  /// Nearest focusable card of [row] beside [from] towards the pressed side.
  static FocusNode? _nextInRow(ScrollableState row, FocusNode node, Rect from, {required bool left}) {
    final scope = node.nearestScope;
    if (scope == null) return null;
    FocusNode? best;
    var bestGap = double.infinity;
    for (final n in scope.traversalDescendants) {
      if (identical(n, node) || !n.canRequestFocus || n.context == null) continue;
      if (_horizontalScrollable(n.context!)?.position != row.position) continue;
      final r = n.rect;
      if (!(r.top < from.bottom && r.bottom > from.top)) continue;
      final gap = left ? from.left - r.right : r.left - from.right;
      if (gap < -from.width * 0.5 || gap >= bestGap) continue;
      if (left ? r.center.dx >= from.center.dx : r.center.dx <= from.center.dx) continue;
      best = n;
      bestGap = gap;
    }
    return best;
  }

  /// The next card is not built yet: scroll the row about one card towards
  /// the pressed side, then focus the card that appeared.
  static bool _scrollRowThenFocus(ScrollableState row, FocusNode node, Rect from, {required bool left}) {
    final pos = row.position;
    final reversed = row.axisDirection == AxisDirection.left;
    final towardsEnd = left == reversed; // visual right in LTR, left in RTL
    final step = from.width * 1.1;
    final target = (pos.pixels + (towardsEnd ? step : -step)).clamp(pos.minScrollExtent, pos.maxScrollExtent);
    if ((target - pos.pixels).abs() < 1) return false;
    pos.jumpTo(target);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!node.hasFocus || node.context == null) return;
      _nextInRow(row, node, node.rect, left: left)?.requestFocus();
    });
    return true;
  }

  /// Focuses the nearest focusable on the same line beside [from], if any.
  static void _focusSameLine(FocusNode node, Rect from, {required bool left}) {
    final scope = node.nearestScope;
    if (scope == null) return;
    FocusNode? best;
    var bestGap = double.infinity;
    for (final n in scope.traversalDescendants) {
      if (identical(n, node) || !n.canRequestFocus || n.context == null) continue;
      final r = n.rect;
      final sameLine = r.top < from.bottom && r.bottom > from.top;
      if (!sameLine) continue;
      final gap = left ? from.left - r.right : r.left - from.right;
      if (gap < -1 || gap >= bestGap) continue;
      best = n;
      bestGap = gap;
    }
    best?.requestFocus();
  }

  /// True when [tile] is the last card the row can show towards the pressed
  /// side: the row cannot scroll further that way and the card touches that
  /// edge. Works for right-to-left rows (Arabic) too.
  static bool _atRowEdge(ScrollableState row, Rect tile, {required bool left}) {
    final box = row.context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return false;
    // Global rect, scale included (the LG / Samsung builds draw the TV
    // design scaled up; offset-global + size-local was off by that scale).
    final view = MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
    final pos = row.position;
    final reversed = row.axisDirection == AxisDirection.left;
    // Can the row reveal more cards on the visual left / right?
    final moreLeft = reversed ? pos.pixels < pos.maxScrollExtent - 1 : pos.pixels > pos.minScrollExtent + 1;
    final moreRight = reversed ? pos.pixels > pos.minScrollExtent + 1 : pos.pixels < pos.maxScrollExtent - 1;
    final slack = tile.width * 0.6;
    if (left) return !moreLeft && tile.left - view.left < slack;
    return !moreRight && view.right - tile.right < slack;
  }

  static ScrollableState? _horizontalScrollable(BuildContext context) {
    for (var s = Scrollable.maybeOf(context);
        s != null;
        s = Scrollable.maybeOf(s.context)) {
      if (s.position.axis == Axis.horizontal) return s;
    }
    return null;
  }

  /// Scroll only as much as needed (Netflix-style): rails slide just enough
  /// to show the tile; the page moves only when the tile would leave the
  /// screen, and snaps to the very top near the banner. The old fixed 25%
  /// alignment cut the top of the banner off whenever its buttons focused.
  void _reveal() {
    final ro = context.findRenderObject();
    if (ro is! RenderBox || !ro.attached || !ro.hasSize) return;
    final duration = _tvAnim(180);
    for (var s = Scrollable.maybeOf(context);
        s != null;
        s = Scrollable.maybeOf(s.context)) {
      final pos = s.position;
      if (pos.axis == Axis.horizontal) {
        pos.ensureVisible(
          ro,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          duration: duration,
          curve: Curves.easeOut,
        );
        pos.ensureVisible(
          ro,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
          duration: duration,
          curve: Curves.easeOut,
        );
        continue;
      }
      // Hero actions: always pin the home list to the top so the full banner
      // (title + art) is visible, not only the focused button strip.
      if (widget.scrollToTopOnFocus) {
        if (pos.pixels > pos.minScrollExtent + 1) {
          unawaited(_tvScrollTo(pos, pos.minScrollExtent, 180));
        }
        continue;
      }
      final view = s.context.findRenderObject();
      if (view is! RenderBox || !view.hasSize) continue;
      final viewH = view.size.height;
      // Position inside the scrollable, in its own units. Global positions
      // were scaled 2x in the LG build (TV canvas fitted to 1920x1080) while
      // viewH was not: lists jumped too far and skipped channels (client
      // 26 Oct #6). Same result on Android TV (scale 1).
      final top = ro.localToGlobal(Offset.zero, ancestor: view).dy;
      final bottom = top + ro.size.height;
      if (top >= viewH * 0.06 && bottom <= viewH * 0.96) continue;
      var target = pos.pixels + top - viewH * 0.2;
      if (target < 160) target = 0;
      target = target.clamp(pos.minScrollExtent, pos.maxScrollExtent);
      if ((target - pos.pixels).abs() > 1) {
        unawaited(_tvScrollTo(pos, target, 180));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.borderRadius;
    final bw = widget.borderWidth;
    final glass = widget.glassFocus;
    final focusScale =
        glass && widget.focusScale == 1.0 ? 1.06 : widget.focusScale;
    final scale = _focused && focusScale != 1.0 ? focusScale : 1.0;
    final glow = glass ? Colors.white : AppColors.cyan;

    Widget body = AnimatedContainer(
      duration: _tvAnim(120),
      curve: Curves.easeOutCubic,
      padding: widget.padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(r),
        border: Border.all(
          // Always same width → no layout jump; invisible when unfocused.
          color: _focused
              ? (glass ? Colors.white : widget.ringColor ?? AppColors.cyan)
              : Colors.transparent,
          width: bw,
        ),
        boxShadow: _focused
            ? [
                BoxShadow(
                  color: glow.withValues(alpha: glass ? 0.55 : 0.42),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
                BoxShadow(
                  color: glow.withValues(alpha: glass ? 0.28 : 0.18),
                  blurRadius: 6,
                  spreadRadius: 0,
                ),
              ]
            : const [],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular((r - bw).clamp(0, r)),
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          // Glass: lighter at the top, like light on glass; no blur (cheap
          // on low-end TV boxes).
          decoration: glass && _focused
              ? BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.42),
                      Colors.white.withValues(alpha: 0.12),
                    ],
                  ),
                )
              : const BoxDecoration(),
          child: widget.focusedOverlay == null
              ? widget.child
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned.fill(child: widget.child),
                    if (_focused) widget.focusedOverlay!,
                  ],
                ),
        ),
      ),
    );

    if (scale != 1.0) {
      body = Transform.scale(
        scale: scale,
        filterQuality: FilterQuality.medium,
        child: body,
      );
    }

    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: MouseRegion(
        onHover: _onPointerHover,
        child: FocusableActionDetector(
        focusNode: _node,
        autofocus: widget.autofocus,
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        onFocusChange: (focused) {
          // The focus ring follows real focus too: a tile that got focus by
          // requestFocus (package moved in the order dialog) showed no ring.
          if (mounted && _focused != focused) setState(() => _focused = focused);
          if (!focused || !mounted) return;
          if (_focusFromPointer) {
            _focusFromPointer = false;
            return;
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _reveal();
          });
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap?.call();
              return null;
            },
          ),
        },
        // With [onLongSelect], OK is handled in [_onKey] (press / hold).
        shortcuts: widget.onLongSelect != null
            ? const <ShortcutActivator, Intent>{
                SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
              }
            : const <ShortcutActivator, Intent>{
                SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
                SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
                SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
              },
        child: GestureDetector(
          onTap: widget.onTap,
          // Own layer per tile: a focus move repaints the two tiles involved,
          // not the whole screen (TCL RTD288O, 2 GB: 40-88 ms raster frames
          // on every remote press, client 21 Oct "severe lag").
          child: RepaintBoundary(child: body),
        ),
      ),
      ),
    );
  }
}

/// Shared Up-at-edge rule for TV content: scroll the nearest vertical list up
/// and retry, or, at the top of the page, move focus to the top menu.
void tvEscapeUpFrom(BuildContext context, VoidCallback? focusTopMenu) {
  ScrollPosition? pos;
  for (var s = Scrollable.maybeOf(context); s != null;
      s = Scrollable.maybeOf(s.context)) {
    if (s.position.axis == Axis.vertical) {
      pos = s.position;
      break;
    }
  }
  if (pos != null && pos.pixels > pos.minScrollExtent + 1) {
    final target = (pos.pixels - pos.viewportDimension * 0.5)
        .clamp(pos.minScrollExtent, pos.maxScrollExtent);
    final p = pos;
    _tvScrollTo(p, target, 160).then((_) {
      final primary = FocusManager.instance.primaryFocus;
      final moved = tvMoveFocus(primary, TraversalDirection.up);
      if (!moved && p.pixels <= p.minScrollExtent + 1) focusTopMenu?.call();
    });
    return;
  }
  focusTopMenu?.call();
}

/// D-pad move from [node] to the nearest focusable in [direction].
///
/// Clears Flutter's directional "came from" memory first. After focus jumped
/// by other means (top menu, scrolling) that memory pointed back at the
/// current tile, so the press "succeeded" without moving and Up/Down needed
/// two presses.
bool tvMoveFocus(FocusNode? node, TraversalDirection direction) {
  final ctx = node?.context;
  if (node == null || ctx == null) return false;
  final scope = node.nearestScope;
  if (scope != null) {
    FocusTraversalGroup.maybeOf(ctx)?.invalidateScopeData(scope);
  }
  return node.focusInDirection(direction);
}

/// Animation length for TV focus / scrolling; zero on slow TVs
/// ([TvPlatformProfile.lowPowerUi]) so each remote press costs one frame.
Duration _tvAnim(int ms) =>
    TvPlatformProfile.lowPowerUi ? Duration.zero : Duration(milliseconds: ms);

/// Scrolls [pos] to [target]: animated, or a jump on slow TVs.
Future<void> _tvScrollTo(ScrollPosition pos, double target, int ms) {
  final d = _tvAnim(ms);
  if (d == Duration.zero) {
    pos.jumpTo(target);
    return Future<void>.value();
  }
  return pos.animateTo(target, duration: d, curve: Curves.easeOut);
}

