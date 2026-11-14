import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'focus_tile.dart';
import 'tv_ui.dart';

/// Package order with the remote (client 17 Oct): OK picks a package up,
/// Up / Down moves it, OK drops it. Returns the new id order, [] for the
/// original order, or null for Cancel.
///
/// Back (client 20 Oct #8): drops a picked-up package; otherwise jumps to the
/// Save / Cancel / Restore buttons without losing the new order (with 100+
/// packages, scrolling down to them was a long walk). Back on the buttons
/// saves, so changes are never thrown away by Back.
Future<List<String>?> showTvArrangePackages(
  BuildContext context, {
  required List<CatalogCategory> categories,
  required String Function(String raw) label,
  required AppCopy copy,
}) {
  return showDialog<List<String>>(
    context: context,
    barrierColor: Colors.black87,
    builder: (_) =>
        _TvArrangeDialog(categories: categories, label: label, copy: copy),
  );
}

class _TvArrangeDialog extends StatefulWidget {
  const _TvArrangeDialog({
    required this.categories,
    required this.label,
    required this.copy,
  });

  final List<CatalogCategory> categories;
  final String Function(String raw) label;
  final AppCopy copy;

  @override
  State<_TvArrangeDialog> createState() => _TvArrangeDialogState();
}

class _TvArrangeDialogState extends State<_TvArrangeDialog> {
  late final List<CatalogCategory> _items = [...widget.categories];
  late final Map<String, FocusNode> _nodes = {
    for (final c in widget.categories) c.id: FocusNode(),
  };
  String? _held;
  final _saveNode = FocusNode(debugLabel: 'arrange-save');
  final _cancelNode = FocusNode(debugLabel: 'arrange-cancel');
  final _resetNode = FocusNode(debugLabel: 'arrange-reset');
  final _scroll = ScrollController();
  static const _rowExtent = 52.0;

  bool get _changed {
    if (_items.length != widget.categories.length) return true;
    for (var i = 0; i < _items.length; i++) {
      if (_items[i].id != widget.categories[i].id) return true;
    }
    return false;
  }

  bool _asking = false;

  /// Back as on LG 6.1.24: drops a held package first; with no change it
  /// closes; after a change it asks "Save changes?" (Save / Discard). It used
  /// to jump to the buttons and save on a second Back without asking.
  Future<void> _onBack() async {
    if (_held != null) {
      setState(() => _held = null);
      return;
    }
    if (!_changed) {
      Navigator.pop(context);
      return;
    }
    if (_asking) return;
    _asking = true;
    final copy = widget.copy;
    final save = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (ctx) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) Navigator.of(ctx).pop(false);
        },
        child: Dialog(
          backgroundColor: const Color(0xFF1A1F2A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 22),
              child: FocusTraversalGroup(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      copy.saveOrderTitle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 22,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      copy.saveOrderBody,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TvButton(
                          autofocus: true,
                          label: copy.discard,
                          onTap: () => Navigator.of(ctx).pop(false),
                        ),
                        const SizedBox(width: TvUi.buttonGap),
                        TvButton(
                          primary: true,
                          label: copy.save,
                          onTap: () => Navigator.of(ctx).pop(true),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    _asking = false;
    if (!mounted) return;
    if (save == true) {
      Navigator.pop(context, [for (final c in _items) c.id]);
    } else {
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    for (final n in _nodes.values) {
      n.dispose();
    }
    _saveNode.dispose();
    _cancelNode.dispose();
    _resetNode.dispose();
    _scroll.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(int i, KeyEvent e) {
    if (_held == null || e is! KeyDownEvent) return KeyEventResult.ignored;
    final up = e.logicalKey == LogicalKeyboardKey.arrowUp;
    final down = e.logicalKey == LogicalKeyboardKey.arrowDown;
    if (!up && !down) return KeyEventResult.ignored;
    final to = up ? i - 1 : i + 1;
    if (to < 0 || to >= _items.length) return KeyEventResult.handled;
    setState(() => _items.insert(to, _items.removeAt(i)));
    _keepVisible(to);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _nodes[_held]?.requestFocus();
    });
    return KeyEventResult.handled;
  }

  /// Scrolls with a held package (client 21 Oct A10 / TV 4): moving it past
  /// the visible edge left it off-screen, so the list never followed. Keeps
  /// one row of context above / below so the next spot is visible too.
  void _keepVisible(int index) {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final top = (index - 1) * _rowExtent;
    final bottom = (index + 2) * _rowExtent - pos.viewportDimension;
    double? target;
    if (top < pos.pixels) target = top;
    if (bottom > pos.pixels) target = bottom;
    if (target == null) return;
    _scroll.jumpTo(target.clamp(pos.minScrollExtent, pos.maxScrollExtent));
  }

  @override
  Widget build(BuildContext context) {
    final copy = widget.copy;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        unawaited(_onBack());
      },
      child: Center(
        child: Material(
          color: const Color(0xFF111622),
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(
            width: 560,
            height: 560,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    copy.arrangePackages,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    copy.arrangePackagesTvHint,
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: FocusTraversalGroup(
                      child: ListView.builder(
                        controller: _scroll,
                        itemCount: _items.length,
                        itemExtent: _rowExtent,
                        itemBuilder: (_, i) {
                          final c = _items[i];
                          final held = _held == c.id;
                          return Padding(
                            // Keyed by package: the focus highlight moves with
                            // the package (it stayed on the old row positions).
                            key: ValueKey(c.id),
                            padding: const EdgeInsets.only(bottom: 6),
                            child: FocusTile(
                              onKeyFirst: (e) => _onKey(i, e),
                              focusNode: _nodes[c.id],
                              autofocus: i == 0,
                              borderRadius: 10,
                              onTap: () =>
                                  setState(() => _held = held ? null : c.id),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                ),
                                decoration: BoxDecoration(
                                  color: held
                                      ? AppColors.cyan.withValues(
                                          alpha: 0.25,
                                        )
                                      : Colors.white.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 32,
                                      child: Text(
                                        '${i + 1}',
                                        style: TextStyle(
                                          color: AppColors.cyan,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        widget.label(c.name),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Icon(
                                      held
                                          ? Icons.unfold_more_rounded
                                          : Icons.drag_handle_rounded,
                                      color: held
                                          ? AppColors.cyan
                                          : Colors.white54,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      TvButton(
                        focusNode: _resetNode,
                        label: copy.resetOrder,
                        onTap: () => Navigator.pop(context, const <String>[]),
                      ),
                      const Spacer(),
                      TvButton(
                        focusNode: _cancelNode,
                        label: copy.cancel,
                        onTap: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 12),
                      TvButton(
                        focusNode: _saveNode,
                        primary: true,
                        label: copy.save,
                        onTap: () => Navigator.pop(context, [
                          for (final c in _items) c.id,
                        ]),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
