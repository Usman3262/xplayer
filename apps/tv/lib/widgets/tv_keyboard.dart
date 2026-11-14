import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'focus_tile.dart';

/// The app's own on-screen keyboard for TV text fields (17 Oct, Amlogic /
/// Droidlogic box): that box's system keyboard never receives the remote's
/// D-pad (its highlight stays on "1"), so nothing could be typed in any
/// field. This keyboard is plain focusable keys, the same on every TV.
/// "System keyboard" falls back to the device keyboard (phone-remote apps
/// type through it).
///
/// Returns true when the user asked for the system keyboard instead.
Future<bool> showTvKeyboard(
  BuildContext context, {
  required TextEditingController controller,
  bool obscure = false,
  int? maxLength,
  bool numbersOnly = false,
  String? label,
  ValueChanged<String>? onChanged,
}) async {
  final useSystem = await showGeneralDialog<bool>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    barrierLabel: 'keyboard',
    barrierColor: Colors.black54,
    pageBuilder: (_, _, _) => _TvKeyboard(
      controller: controller,
      obscure: obscure,
      maxLength: maxLength,
      numbersOnly: numbersOnly,
      label: label,
      onChanged: onChanged,
    ),
  );
  return useSystem ?? false;
}

enum _Layout { lower, upper, symbols, arabic }

const _rows = <_Layout, List<String>>{
  _Layout.lower: ['1234567890', 'qwertyuiop', 'asdfghjkl@', 'zxcvbnm._-'],
  _Layout.upper: ['1234567890', 'QWERTYUIOP', 'ASDFGHJKL@', 'ZXCVBNM._-'],
  _Layout.symbols: ['!#\$%&*+=?/', '()[]{}<>:;', '\'",~^|\\`€£', '1234567890'],
  _Layout.arabic: ['ضصثقفغعهخح', 'شسيبلاتنمك', 'ئءؤرىةوزظط', 'ذدجآأإ٠١٢٣'],
};

class _TvKeyboard extends StatefulWidget {
  const _TvKeyboard({
    required this.controller,
    required this.obscure,
    this.maxLength,
    this.numbersOnly = false,
    this.label,
    this.onChanged,
  });

  final ValueChanged<String>? onChanged;
  final TextEditingController controller;
  final bool obscure;
  final int? maxLength;
  final bool numbersOnly;
  final String? label;

  @override
  State<_TvKeyboard> createState() => _TvKeyboardState();
}

class _TvKeyboardState extends State<_TvKeyboard> {
  late _Layout _layout =
      widget.numbersOnly ? _Layout.symbols : _Layout.lower;
  bool _reveal = false;

  TextEditingController get _c => widget.controller;

  void _type(String ch) {
    final max = widget.maxLength;
    if (max != null && _c.text.characters.length >= max) return;
    _set(_c.text + ch);
    // One capital, then back to lower case (like a phone keyboard).
    if (_layout == _Layout.upper) setState(() => _layout = _Layout.lower);
  }

  void _backspace() {
    final t = _c.text.characters;
    if (t.isEmpty) return;
    _set(t.skipLast(1).toString());
  }

  void _set(String text) {
    _c.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    // Setting the controller does not run the field's onChanged (search
    // reacts to it).
    widget.onChanged?.call(text);
    setState(() {});
  }

  void _done() => Navigator.of(context).pop(false);

  Widget _key(
    String label, {
    required VoidCallback onTap,
    double width = 56,
    IconData? icon,
    bool accent = false,
    bool autofocus = false,
  }) {
    return Padding(
      padding: const EdgeInsets.all(3),
      child: SizedBox(
        width: width,
        height: 46,
        child: FocusTile(
          autofocus: autofocus,
          borderRadius: 10,
          onTap: onTap,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent
                  ? AppColors.cyan
                  : Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: icon != null
                ? Icon(icon, size: 22, color: accent ? Colors.black : Colors.white)
                : Text(
                    label,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: accent ? Colors.black : Colors.white,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows[_layout]!;
    final text = _c.text;
    final shown = widget.obscure && !_reveal
        ? '•' * text.characters.length
        : text;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Material(
        color: const Color(0xFF0E131D),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        child: Directionality(
          // Keys are a physical grid: same order in Arabic.
          textDirection: TextDirection.ltr,
          child: Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: (_, e) {
              if (e is! KeyDownEvent) return KeyEventResult.ignored;
              final k = e.logicalKey;
              // Back closes through the route (system back). Handling it
              // here too made one press also reach the screen below
              // ("Exit APP 4K?").
              // A real keyboard / remote with keys still types here.
              final ch = e.character;
              if (ch != null && ch.length == 1 && ch.codeUnitAt(0) >= 32) {
                _type(ch);
                return KeyEventResult.handled;
              }
              if (k == LogicalKeyboardKey.backspace) {
                _backspace();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: FocusTraversalGroup(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 16, 28, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // What has been typed (the field itself may be hidden
                    // behind the keyboard).
                    Container(
                      width: 720,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.cyan),
                      ),
                      child: Row(
                        children: [
                          if (widget.label != null) ...[
                            Text(
                              widget.label!,
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            child: Text(
                              shown.isEmpty ? ' ' : shown,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textDirection: TextDirection.ltr,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            '|',
                            style: TextStyle(
                              color: AppColors.cyan,
                              fontSize: 20,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (var r = 0; r < rows.length; r++)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < rows[r].characters.length; i++)
                            _key(
                              rows[r].characters.elementAt(i),
                              autofocus: r == 1 && i == 0,
                              onTap: () =>
                                  _type(rows[r].characters.elementAt(i)),
                            ),
                        ],
                      ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _key(
                          'shift',
                          icon: Icons.keyboard_capslock_rounded,
                          onTap: () => setState(
                            () => _layout = _layout == _Layout.upper
                                ? _Layout.lower
                                : _Layout.upper,
                          ),
                        ),
                        _key(
                          _layout == _Layout.symbols ? 'abc' : '#+=',
                          width: 70,
                          onTap: () => setState(
                            () => _layout = _layout == _Layout.symbols
                                ? _Layout.lower
                                : _Layout.symbols,
                          ),
                        ),
                        _key(
                          _layout == _Layout.arabic ? 'EN' : 'ع',
                          onTap: () => setState(
                            () => _layout = _layout == _Layout.arabic
                                ? _Layout.lower
                                : _Layout.arabic,
                          ),
                        ),
                        _key(
                          'space',
                          width: 176,
                          icon: Icons.space_bar_rounded,
                          onTap: () => _type(' '),
                        ),
                        _key(
                          'delete',
                          icon: Icons.backspace_rounded,
                          onTap: _backspace,
                        ),
                        _key('Clear', width: 70, onTap: () => _set('')),
                        if (widget.obscure)
                          _key(
                            'show',
                            icon: _reveal
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                            onTap: () => setState(() => _reveal = !_reveal),
                          ),
                        _key(
                          'system',
                          icon: Icons.keyboard_alt_outlined,
                          onTap: () => Navigator.of(context).pop(true),
                        ),
                        _key(
                          'Done',
                          width: 90,
                          accent: true,
                          onTap: _done,
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
  }
}
