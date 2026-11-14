import 'dart:async';

import 'package:data/data.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_log.dart';
import '../core/session_controller.dart';
import '../router/app_router.dart';
import 'action_feedback.dart';

/// Polls pending login challenges on the priority phone and shows Allow/Deny.
///
/// Mounted at [MaterialApp] so it keeps running on profiles / settings / shell.
/// Always polls while logged in — backend already emits `loginApprovalRequired`
/// on TV; gating on `features.deviceLoginApproval` alone skipped the popup when
/// login/`/me` omitted the flag.
class LoginChallengeHost extends ConsumerStatefulWidget {
  const LoginChallengeHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<LoginChallengeHost> createState() => _LoginChallengeHostState();
}

class _LoginChallengeHostState extends ConsumerState<LoginChallengeHost>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _promptOpen = false;
  bool _tickInFlight = false;
  final Set<String> _handled = {};

  /// While a TV/new-device may be waiting (5 min TTL), poll often.
  // Push brings a new sign-in request at once; this is the backup while the
  // app is open. Was 5 s on every phone (21 Oct).
  static const _loggedInInterval = Duration(seconds: 12);
  static const _notPrimaryInterval = Duration(seconds: 60);
  static const _loggedOutInterval = Duration(seconds: 45);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _schedule(_loggedInInterval);
      _tick();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _tick();
    }
  }

  void _schedule(Duration interval) {
    _timer?.cancel();
    _timer = Timer(interval, () {
      _tick();
    });
  }

  bool get _shouldPoll {
    final session = ref.read(sessionProvider);
    if (!session.isLoggedIn) return false;
    final user = session.user;
    // Prefer flag when present; also poll if this phone is priority, or if
    // features were never hydrated (login payload often omits them).
    if (user?.deviceLoginApproval == true) return true;
    if (user?.priorityDevice == true) return true;
    if (session.devices.any((d) => d.isThisDevice && d.isPriority)) {
      return true;
    }
    // Optimistic: empty pending is cheap; missing popup was the worse failure.
    return true;
  }

  Future<void> _tick() async {
    if (!mounted || _promptOpen || _tickInFlight) {
      _schedule(_loggedInInterval);
      return;
    }
    if (!_shouldPoll) {
      _schedule(_loggedOutInterval);
      return;
    }

    _tickInFlight = true;
    List<LoginChallengeDto> pending = const [];
    Object? err;
    try {
      pending = await ref
          .read(sessionProvider.notifier)
          .pendingLoginChallenges();
    } catch (e) {
      err = e;
      pending = const [];
    } finally {
      _tickInFlight = false;
    }

    if (!mounted) return;

    if (err != null) {
      AppLog.info('LoginChallenge', 'pending poll failed: $err');
      _schedule(_loggedInInterval);
      return;
    }

    if (pending.isEmpty) {
      // Not the primary phone: the server refuses this call (403). Asking
      // every 5 s wasted data and battery (19 Oct); check rarely in case this
      // phone becomes primary.
      // The server now answers other phones with an empty list (it used to
      // 403), so slow down by what we know about this phone instead.
      final forbidden = ref
          .read(sessionProvider.notifier)
          .pendingChallengesForbidden;
      final devices = ref.read(sessionProvider).devices;
      final knownNotPrimary =
          devices.isNotEmpty &&
          !devices.any((d) => d.isThisDevice && d.isPriority);
      _schedule(
        forbidden
            ? const Duration(minutes: 2)
            : knownNotPrimary
            ? _notPrimaryInterval
            : _loggedInInterval,
      );
      return;
    }

    AppLog.info(
      'LoginChallenge',
      'pending=${pending.length} '
          'first=${pending.first.challengeId} '
          'status=${pending.first.status}',
    );

    final next = pending.firstWhere(
      (c) => c.isPending && !_handled.contains(c.challengeId),
      orElse: () => pending.first,
    );
    if (!next.isPending || _handled.contains(next.challengeId)) {
      _schedule(_loggedInInterval);
      return;
    }

    await _showPrompt(next);
    if (!mounted) return;
    _schedule(_loggedInInterval);
  }

  /// This host sits in MaterialApp.router's `builder`, i.e. ABOVE the app's
  /// Navigator, so its own context cannot open dialogs (showDialog threw and
  /// the Allow / Deny prompt never appeared — 6 Nov). Use the router's
  /// navigator instead.
  BuildContext? get _navContext =>
      ref.read(routerProvider).routerDelegate.navigatorKey.currentContext;

  Future<void> _showPrompt(LoginChallengeDto challenge) async {
    if (!mounted) return;
    final nav = _navContext;
    if (nav == null || !nav.mounted) {
      // Navigator not ready yet (app starting): ask again on the next tick.
      AppLog.info('LoginChallenge', 'navigator not ready; prompt next tick');
      return;
    }
    _promptOpen = true;
    final copy = AppCopy.ofLanguage(ref.read(sessionProvider).language);
    final name = challenge.deviceName ?? 'Device';
    final platform = challenge.platform ?? '';
    AppLog.info(
      'LoginChallenge',
      'prompt allow/deny id=${challenge.challengeId} device=$name',
    );
    bool? allow;
    try {
      allow = await showDialog<bool>(
        context: nav,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF111622),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
          ),
          title: Text(copy.newSignInTitle),
          content: Text(copy.newSignInBody(name, platform)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                copy.denySignIn,
                style: TextStyle(color: AppColors.danger),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.cyan,
                foregroundColor: Colors.black,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(copy.allowSignIn),
            ),
          ],
        ),
      );
    } catch (e) {
      // Never leave _promptOpen stuck: that silenced every later request.
      AppLog.info('LoginChallenge', 'prompt failed: $e');
      _promptOpen = false;
      return;
    }
    _handled.add(challenge.challengeId);
    try {
      if (allow == true) {
        await ref
            .read(sessionProvider.notifier)
            .allowLoginChallenge(challenge.challengeId);
        AppLog.info('LoginChallenge', 'allowed ${challenge.challengeId}');
      } else {
        await ref
            .read(sessionProvider.notifier)
            .denyLoginChallenge(challenge.challengeId);
        AppLog.info('LoginChallenge', 'denied ${challenge.challengeId}');
      }
    } on ApiException catch (e) {
      final ctx = _navContext;
      if (mounted && ctx != null && ctx.mounted) {
        await ActionFeedback.error(
          ctx,
          title: e.isPriorityRequired
              ? copy.priorityRequiredTitle
              : copy.revokeFailed,
          message: e.isPriorityRequired
              ? copy.priorityRequiredBody
              : ActionFeedback.clean(e),
        );
      }
    } catch (e) {
      final ctx = _navContext;
      if (mounted && ctx != null && ctx.mounted) {
        await ActionFeedback.error(
          ctx,
          title: copy.revokeFailed,
          message: ActionFeedback.clean(e),
        );
      }
    } finally {
      _promptOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
