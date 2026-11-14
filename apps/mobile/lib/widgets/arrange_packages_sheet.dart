import 'package:design_system/design_system.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';

/// Lets the user order the packages of a section (client 17 Oct: "foreign
/// movies first, then Arabic, then 4K"). Returns the new id order, an empty
/// list for "original order", or null when cancelled.
Future<List<String>?> showArrangePackagesSheet(
  BuildContext context, {
  required List<CatalogCategory> categories,
  required String Function(String raw) label,
  required AppCopy copy,
}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _ArrangeSheet(
      categories: categories,
      label: label,
      copy: copy,
    ),
  );
}

class _ArrangeSheet extends StatefulWidget {
  const _ArrangeSheet({
    required this.categories,
    required this.label,
    required this.copy,
  });

  final List<CatalogCategory> categories;
  final String Function(String raw) label;
  final AppCopy copy;

  @override
  State<_ArrangeSheet> createState() => _ArrangeSheetState();
}

class _ArrangeSheetState extends State<_ArrangeSheet> {
  late final List<CatalogCategory> _items = [...widget.categories];

  bool get _changed {
    for (var i = 0; i < _items.length; i++) {
      if (_items[i].id != widget.categories[i].id) return true;
    }
    return false;
  }

  /// As on LG 6.1.24: closing after a change (Back, swipe down, tap outside)
  /// asks "Save changes?"; with no change it just closes.
  Future<void> _askSave() async {
    final copy = widget.copy;
    final save = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: Text(copy.saveOrderTitle),
        content: Text(copy.saveOrderBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(copy.discard),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(copy.save),
          ),
        ],
      ),
    );
    if (!mounted || save == null) return;
    Navigator.pop(context, save ? [for (final c in _items) c.id] : null);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_changed,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _askSave();
      },
      child: _sheet(context),
    );
  }

  Widget _sheet(BuildContext context) {
    final copy = widget.copy;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.8,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
              child: Text(
                copy.arrangePackages,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                copy.arrangePackagesHint,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
            Expanded(
              child: ReorderableListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _items.length,
                onReorder: (from, to) {
                  setState(() {
                    if (to > from) to -= 1;
                    _items.insert(to, _items.removeAt(from));
                  });
                },
                itemBuilder: (_, i) {
                  final c = _items[i];
                  return Card(
                    key: ValueKey(c.id),
                    color: AppColors.surfaceElevated,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      leading: Text(
                        '${i + 1}',
                        style: TextStyle(color: AppColors.cyan),
                      ),
                      title: Text(
                        widget.label(c.name),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: ReorderableDragStartListener(
                        index: i,
                        child: const Icon(Icons.drag_handle_rounded),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, const <String>[]),
                    child: Text(copy.resetOrder),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(copy.cancel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.pop(
                      context,
                      [for (final c in _items) c.id],
                    ),
                    child: Text(copy.save),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
