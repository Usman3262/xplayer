import 'package:data/data.dart' show Diag;
import 'package:flutter/services.dart';

import '../widgets/focus_tile.dart';
import '../widgets/tv_keyboard.dart';
import 'package:flutter/material.dart' show TextField;
import 'package:flutter/widgets.dart';

/// Android TV remote handling for text fields, run before the focus tree:
/// - OK (DPAD center) / Enter on a focused field opens the on-screen
///   keyboard. Screens map OK/Enter to ActivateIntent for buttons, which
///   swallowed the key, so the keyboard never opened.
/// - Up/Down leave a single-line field (they only moved the caret before).
/// Set by the TV shell while it is mounted: moves focus to the top menu.
VoidCallback? tvFocusTopMenu;

void installTvTextInputKeyHandler() {
  HardwareKeyboard.instance.addHandler(_openKeyboardOnSelect);
  FocusManager.instance.addListener(_keepSystemKeyboardClosed);
}

/// Field for which the user chose "System keyboard" on the app keyboard.
EditableTextState? _systemKeyboardFor;

/// A text field that gains focus (remote move, or focus coming back when the
/// app keyboard closes) makes Flutter show the system keyboard. On boxes
/// whose system keyboard cannot take the D-pad it then sat on top of the
/// screen and swallowed the next presses (17 Oct). The system keyboard
/// now appears only after the user picks it on the app keyboard.
void _keepSystemKeyboardClosed() {
  final editable = _focusedEditable();
  if (editable == null) {
    _systemKeyboardFor = null;
    return;
  }
  if (identical(editable, _systemKeyboardFor)) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final now = _focusedEditable();
    if (now != null && !identical(now, _systemKeyboardFor)) {
      SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    }
  });
}

final _openKeys = <LogicalKeyboardKey>{
  LogicalKeyboardKey.select,
  LogicalKeyboardKey.enter,
  LogicalKeyboardKey.numpadEnter,
  LogicalKeyboardKey.gameButtonA,
};

/// OK key whose press started on a text field; the keyboard opens on its
/// release. Opening on key-down let the keyboard appear fast enough to take
/// the key-up as a press of its highlighted key (an extra letter).
LogicalKeyboardKey? _pendingOpenKey;

bool _openKeyboardOnSelect(KeyEvent event) {
  final key = event.logicalKey;
  if (event is KeyUpEvent) {
    if (_pendingOpenKey != key) return false;
    _pendingOpenKey = null;
    // Give the remote's key-up time to clear before the keyboard appears.
    Future<void>.delayed(const Duration(milliseconds: 100), () async {
      final editable = _focusedEditable();
      if (editable == null || !editable.mounted || editable.widget.readOnly) {
        return;
      }
      // The app's own keyboard first: some TV boxes' system keyboards never
      // get the D-pad (17 Oct, Amlogic box), so nothing could be typed.
      final w = editable.widget;
      final field = editable.context.findAncestorWidgetOfExactType<TextField>();
      int? maxLength = field?.maxLength;
      for (final f in w.inputFormatters ?? const <TextInputFormatter>[]) {
        if (f is LengthLimitingTextInputFormatter) maxLength ??= f.maxLength;
      }
      final useSystem = await showTvKeyboard(
        editable.context,
        controller: w.controller,
        obscure: w.obscureText,
        maxLength: maxLength,
        numbersOnly: w.keyboardType == TextInputType.number ||
            w.keyboardType == TextInputType.phone,
        label: field?.decoration?.labelText ?? field?.decoration?.hintText,
        onChanged: w.onChanged,
      );
      if (!editable.mounted) return;
      if (useSystem) {
        _systemKeyboardFor = editable;
        _guardAgainstOpeningKeystroke(editable);
        editable.requestKeyboard();
      } else {
        // Focus is back on the field: keep the system keyboard closed.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
        });
      }
    });
    return true;
  }
  if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
  final isOpen = _openKeys.contains(key);
  final isVertical =
      key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.arrowUp;
  if (!isOpen && !isVertical) return false;
  final node = FocusManager.instance.primaryFocus;
  final editable = _focusedEditable();
  if (node == null || editable == null) return false;

  if (isOpen) {
    if (editable.widget.readOnly) return false;
    // Swallow the press (and repeats); open on release.
    _pendingOpenKey = key;
    return true;
  }

  // Up/Down inside a single-line field only move the caret, so a remote
  // could never leave the field: move focus instead — but only while the
  // on-screen keyboard is closed. Gboard keeps the D-pad to itself, but some
  // TV keyboards (Amlogic / Droidlogic box, 17 Oct video) also pass the
  // arrows to the app: the first Down inside the keyboard moved focus to the
  // next field, which closed the keyboard before anything could be typed.
  // The keyboard's height (adjustResize insets) says whether it is open.
  if ((editable.widget.maxLines ?? 1) != 1) return false;
  if (_keyboardVisible()) {
    Diag.dev('IME open: ${key.keyLabel} kept for the keyboard');
    return true;
  }
  final moved = tvMoveFocus(
    node,
    key == LogicalKeyboardKey.arrowDown
        ? TraversalDirection.down
        : TraversalDirection.up,
  );
  // Top-of-page field (e.g. Search): Up goes to the top menu.
  if (!moved && key == LogicalKeyboardKey.arrowUp) tvFocusTopMenu?.call();
  return true;
}

/// True while the system on-screen keyboard covers part of the window.
bool _keyboardVisible() {
  for (final v in WidgetsBinding.instance.platformDispatcher.views) {
    if (v.viewInsets.bottom > 0) return true;
  }
  return false;
}

EditableTextState? _focusedEditable() {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return null;
  return ctx is StatefulElement && ctx.state is EditableTextState
      ? ctx.state as EditableTextState
      : ctx.findAncestorStateOfType<EditableTextState>();
}

/// Some Android TV keyboards (seen with Gboard for TV) enter their
/// highlighted key on the same OK press that opened them, adding one stray
/// character. For a short window after opening from the remote, undo a single
/// character inserted at the caret; anything later is the user's typing.
void _guardAgainstOpeningKeystroke(EditableTextState editable) {
  final controller = editable.widget.controller;
  final before = controller.value;
  final sel = before.selection;
  if (!sel.isValid || !sel.isCollapsed) return;
  final caret = sel.baseOffset;
  var done = false;
  late final VoidCallback listener;
  void stop() {
    if (done) return;
    done = true;
    controller.removeListener(listener);
  }

  listener = () {
    final now = controller.value;
    if (now.text == before.text) return; // selection/composing only
    final inserted = now.text.length == before.text.length + 1 &&
        now.text.startsWith(before.text.substring(0, caret)) &&
        now.text.endsWith(before.text.substring(caret));
    stop();
    if (inserted) {
      // Restore after this notification completes.
      Future<void>.microtask(() => controller.value = before);
    }
  };
  controller.addListener(listener);
  Future<void>.delayed(const Duration(milliseconds: 700), stop);
}
