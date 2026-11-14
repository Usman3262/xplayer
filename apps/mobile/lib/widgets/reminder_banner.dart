import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/program_reminders.dart';
import '../core/session_controller.dart';

/// "Programme is starting" banner over every screen (same as the TV app).
/// Watch opens the channel; it closes by itself after a minute.
class ReminderBanner extends ConsumerStatefulWidget {
  const ReminderBanner({super.key, required this.child, required this.onWatch});

  final Widget child;
  final void Function(String channelId) onWatch;

  @override
  ConsumerState<ReminderBanner> createState() => _ReminderBannerState();
}

class _ReminderBannerState extends ConsumerState<ReminderBanner> {
  Timer? _auto;

  void _close() {
    _auto?.cancel();
    ref.read(programRemindersProvider.notifier).clearDue();
  }

  @override
  void dispose() {
    _auto?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(programRemindersProvider.select((s) => s.due), (prev, due) {
      if (due == null || prev?.key == due.key) return;
      _auto?.cancel();
      _auto = Timer(const Duration(minutes: 1), _close);
    });
    final due = ref.watch(programRemindersProvider.select((s) => s.due));
    final copy = AppCopy.ofLanguage(
      ref.watch(sessionProvider.select((s) => s.language)),
    );
    return Stack(
      children: [
        widget.child,
        if (due != null)
          Positioned(
            left: 12,
            right: 12,
            top: 0,
            child: SafeArea(
              child: Material(
                color: const Color(0xFF141A26),
                elevation: 8,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        copy.reminderStarting(due.programTitle),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        due.channelTitle,
                        style: const TextStyle(color: Colors.white70),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(onPressed: _close, child: Text(copy.cancel)),
                          FilledButton.icon(
                            onPressed: () {
                              final id = due.channelId;
                              _close();
                              widget.onWatch(id);
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.cyan,
                              foregroundColor: Colors.black,
                            ),
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: Text(copy.watchNow),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
