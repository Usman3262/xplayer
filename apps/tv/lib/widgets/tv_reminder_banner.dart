import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/tv_locale.dart';
import '../core/tv_program_reminders.dart';
import 'tv_poster.dart' show TvGlass;
import 'tv_ui.dart';

/// "Programme is starting" alert over every screen (client 16 Oct #08).
/// Takes focus on Watch; Dismiss or Back closes it and gives focus back.
/// Closes by itself after a minute.
class TvReminderBanner extends ConsumerStatefulWidget {
  const TvReminderBanner({super.key, required this.child, required this.onWatch});

  final Widget child;

  /// Opens the live channel (the app's router; this sits above it).
  final void Function(String channelId) onWatch;

  @override
  ConsumerState<TvReminderBanner> createState() => _TvReminderBannerState();
}

class _TvReminderBannerState extends ConsumerState<TvReminderBanner> {
  final _watch = FocusNode(debugLabel: 'reminder-watch');
  FocusNode? _before;
  Timer? _auto;

  void _close() {
    _auto?.cancel();
    ref.read(tvProgramRemindersProvider.notifier).clearDue();
    final b = _before;
    _before = null;
    if (b != null && b.context != null) b.requestFocus();
  }

  @override
  void dispose() {
    _auto?.cancel();
    _watch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(tvProgramRemindersProvider.select((s) => s.due), (prev, due) {
      if (due == null || prev?.key == due.key) return;
      _before = FocusManager.instance.primaryFocus;
      _auto?.cancel();
      _auto = Timer(const Duration(minutes: 1), _close);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _watch.requestFocus();
      });
    });
    final due = ref.watch(tvProgramRemindersProvider.select((s) => s.due));
    final copy = AppCopy.ofLanguage(ref.watch(tvLanguageProvider));
    return Stack(
      children: [
        widget.child,
        if (due != null)
          PositionedDirectional(
            top: 24,
            end: 24,
            child: Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onKeyEvent: (_, e) {
                if (e is KeyDownEvent &&
                    (e.logicalKey == LogicalKeyboardKey.goBack ||
                        e.logicalKey == LogicalKeyboardKey.escape)) {
                  _close();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Material(
                color: Colors.transparent,
                child: TvGlass(
                  radius: 16,
                  tint: AppColors.cyan,
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: 380,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          copy.reminderStarting(due.programTitle),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          due.channelTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            TvButton(
                              primary: true,
                              focusNode: _watch,
                              icon: Icons.play_arrow_rounded,
                              label: copy.watchNow,
                              onTap: () {
                                final id = due.channelId;
                                _before = null;
                                _close();
                                widget.onWatch(id);
                              },
                            ),
                            const SizedBox(width: 10),
                            TvButton(
                              icon: Icons.close_rounded,
                              label: copy.cancel,
                              onTap: _close,
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
      ],
    );
  }
}
