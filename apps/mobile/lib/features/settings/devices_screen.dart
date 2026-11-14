import 'package:data/data.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/session_controller.dart';
import '../../widgets/action_feedback.dart';

class DevicesScreen extends ConsumerStatefulWidget {
  const DevicesScreen({super.key});

  @override
  ConsumerState<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends ConsumerState<DevicesScreen> {
  bool _loading = false;
  String? _busyDeviceId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh(silent: true));
  }

  AppCopy get _copy =>
      AppCopy.ofLanguage(ref.read(sessionProvider).language);

  Future<void> _refresh({bool silent = false}) async {
    if (!mounted) return;
    setState(() => _loading = true);
    final copy = _copy;
    try {
      await ref.read(sessionProvider.notifier).refreshDevicesAndSessions();
      if (!mounted || silent) return;
      ActionFeedback.snack(
        context,
        title: copy.devices,
        message: copy.devicesRefreshed,
      );
    } catch (e) {
      if (!mounted) return;
      await ActionFeedback.error(
        context,
        title: copy.couldNotLoadDevices,
        message: ActionFeedback.clean(e),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _rename(String id, String current) async {
    if (!mounted) return;
    final copy = _copy;
    final name = await showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => _RenameDeviceDialog(initialName: current, copy: copy),
    );
    if (!mounted) return;
    if (name == null || name.isEmpty || name == current) return;
    setState(() => _busyDeviceId = id);
    try {
      await ref.read(sessionProvider.notifier).renameDevice(id, name);
      if (!mounted) return;
      ActionFeedback.snack(
        context,
        title: copy.deviceRenamed,
        message: copy.deviceLabelUpdated,
      );
    } catch (e) {
      if (!mounted) return;
      await ActionFeedback.error(
        context,
        title: copy.renameFailed,
        message: ActionFeedback.clean(e),
      );
    } finally {
      if (mounted) setState(() => _busyDeviceId = null);
    }
  }

  Future<void> _revoke(String id, String name, {required bool isPriority}) async {
    final copy = _copy;
    if (!DeviceTrustPolicy.canRevokeDevice(targetIsPriority: isPriority)) {
      await ActionFeedback.error(
        context,
        title: copy.cannotRevokePrimaryTitle,
        message: copy.cannotRevokePrimaryBody,
      );
      return;
    }
    final ok = await ActionFeedback.confirm(
      context,
      title: copy.revokeThisDevice,
      message: copy.revokeDeviceMessage(name),
      confirmLabel: copy.revoke,
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busyDeviceId = id);
    try {
      await ref.read(sessionProvider.notifier).revokeDevice(id);
      if (!mounted) return;
      ActionFeedback.snack(
        context,
        title: copy.deviceRevoked,
        message: copy.deviceNoLongerLinked(name),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      await ActionFeedback.error(
        context,
        title: e.isPriorityRequired
            ? copy.cannotRevokePrimaryTitle
            : copy.revokeFailed,
        message: e.isPriorityRequired
            ? copy.cannotRevokePrimaryBody
            : ActionFeedback.clean(e),
      );
    } catch (e) {
      if (!mounted) return;
      await ActionFeedback.error(
        context,
        title: copy.revokeFailed,
        message: ActionFeedback.clean(e),
      );
    } finally {
      if (mounted) setState(() => _busyDeviceId = null);
    }
  }

  Future<void> _setPriority(String id) async {
    final copy = _copy;
    setState(() => _busyDeviceId = id);
    try {
      await ref.read(sessionProvider.notifier).setPriorityDevice(id);
      if (!mounted) return;
      ActionFeedback.snack(
        context,
        title: copy.priorityUpdated,
        message: copy.priorityDevice,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      await ActionFeedback.error(
        context,
        title: e.isPriorityRequired
            ? copy.priorityRequiredTitle
            : copy.priorityUpdateFailed,
        message: e.isPriorityRequired
            ? copy.priorityRequiredBody
            : ActionFeedback.clean(e),
      );
    } catch (e) {
      if (!mounted) return;
      await ActionFeedback.error(
        context,
        title: copy.priorityUpdateFailed,
        message: ActionFeedback.clean(e),
      );
    } finally {
      if (mounted) setState(() => _busyDeviceId = null);
    }
  }

  Future<void> _revokeAll() async {
    final copy = _copy;
    final devices = ref.read(sessionProvider).devices;
    final hasPriority = devices.any((d) => d.isPriority);
    final iAmPriority = devices.any((d) => d.isThisDevice && d.isPriority);
    if (!DeviceTrustPolicy.canRevokeAll(
      actorIsPriority: iAmPriority,
      accountHasPriority: hasPriority,
    )) {
      await ActionFeedback.error(
        context,
        title: copy.cannotRevokeAllWithoutPrimaryTitle,
        message: copy.cannotRevokeAllWithoutPrimaryBody,
      );
      return;
    }
    final ok = await ActionFeedback.confirm(
      context,
      title: copy.revokeAllDevicesTitle,
      message: copy.revokeAllDevicesMessage,
      confirmLabel: copy.revokeAllDevices,
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _loading = true);
    try {
      await ref.read(sessionProvider.notifier).revokeAllDevices();
      if (!mounted) return;
      ActionFeedback.snack(
        context,
        title: copy.revokeAllDone,
        message: copy.revokeAllDevicesMessage,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      await ActionFeedback.error(
        context,
        title: e.isPriorityRequired
            ? copy.cannotRevokeAllWithoutPrimaryTitle
            : copy.revokeFailed,
        message: e.isPriorityRequired
            ? copy.cannotRevokeAllWithoutPrimaryBody
            : ActionFeedback.clean(e),
      );
    } catch (e) {
      if (!mounted) return;
      await ActionFeedback.error(
        context,
        title: copy.revokeFailed,
        message: ActionFeedback.clean(e),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final copy = AppCopy.ofLanguage(session.language);
    final user = session.user;
    final showPriority = user?.priorityDevice == true;
    final iAmPriority = session.devices.any((d) => d.isThisDevice && d.isPriority);
    final hasPriority = session.devices.any((d) => d.isPriority);
    final canRevokeAll = DeviceTrustPolicy.canRevokeAll(
      actorIsPriority: iAmPriority,
      accountHasPriority: hasPriority,
    );
    return Scaffold(
      backgroundColor: Colors.black,
      body: AppAtmosphere(
        intensity: 0.85,
        child: SafeArea(
          child: RefreshIndicator(
            color: AppColors.cyan,
            onRefresh: () => _refresh(silent: true),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                Row(
                  children: [
                    IconButton(
                      // C7: if opened via go() with an empty stack, pop is a
                      // no-op and the screen feels frozen — fall back to Settings.
                      onPressed: () {
                        if (context.canPop()) {
                          context.pop();
                        } else {
                          context.go('/settings');
                        }
                      },
                      style: IconButton.styleFrom(
                        backgroundColor:
                            AppColors.surface.withValues(alpha: 0.7),
                        side: BorderSide(color: AppColors.border),
                      ),
                      icon: const AppBackIcon(size: 16),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: AppLogo(height: 44, alignToStart: true),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
                const SizedBox(height: 18),
                TechBadge(copy.devicesBadge, tone: BadgeTone.magenta),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: NeonGlowText(
                        copy.devices,
                        color: AppColors.cyan,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 30,
                          letterSpacing: -0.4,
                        ),
                      ).animate().fadeIn(duration: 300.ms),
                    ),
                    if (_loading)
                      AppLoader.inline(size: 18)
                    else
                      TechBadge(
                        copy.devicesCount(session.devices.length),
                        compact: true,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  copy.devicesLimitHint(user?.deviceLimit ?? 5),
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),
                if (session.devices.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      copy.noDevicesYet,
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                for (final d in session.devices)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xCC111622),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: AppColors.cyan.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.cyan.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Icon(
                            d.platform.contains('TV')
                                ? Icons.tv_rounded
                                : Icons.smartphone_rounded,
                            color: AppColors.cyan,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                d.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                d.joinedAt == null
                                    ? '${d.platform} · Last active ${d.lastActive}'
                                    : '${d.platform} · Joined ${d.joinedAt} · Last active ${d.lastActive}',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  if (d.isThisDevice)
                                    TechBadge(copy.thisDevice, compact: true),
                                  if (d.hasHardwareKey)
                                    TechBadge(copy.hardwareKey, compact: true, tone: BadgeTone.gold),
                                  if (d.isPriority)
                                    TechBadge(
                                      copy.priorityDevice,
                                      compact: true,
                                      tone: BadgeTone.magenta,
                                    ),
                                  if (d.unreachable || d.isStale)
                                    TechBadge(
                                      d.unreachable
                                          ? copy.deviceUnreachableBadge
                                          : copy.deviceStaleBadge,
                                      compact: true,
                                      tone: BadgeTone.gold,
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        if (_busyDeviceId == d.id)
                          SizedBox(
                            width: 40,
                            height: 40,
                            child: Center(child: AppLoader.button(size: 28)),
                          )
                        else ...[
                          // Only the current priority phone may transfer priority.
                          if (showPriority &&
                              iAmPriority &&
                              d.canBePriority &&
                              !d.isPriority)
                            IconButton(
                              tooltip: copy.setAsPriority,
                              onPressed: () => _setPriority(d.id),
                              icon: Icon(
                                Icons.star_outline_rounded,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          IconButton(
                            tooltip: copy.rename,
                            onPressed: () => _rename(d.id, d.name),
                            icon: Icon(
                              Icons.edit_rounded,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          if (!d.isThisDevice &&
                              DeviceTrustPolicy.canRevokeDevice(
                                targetIsPriority: d.isPriority,
                              ))
                            IconButton(
                              onPressed: () => _revoke(
                                d.id,
                                d.name,
                                isPriority: d.isPriority,
                              ),
                              icon: Icon(
                                Icons.link_off_rounded,
                                color: AppColors.danger,
                              ),
                            )
                          else if (!d.isThisDevice && d.isPriority)
                            IconButton(
                              tooltip: copy.cannotRevokePrimaryTitle,
                              onPressed: () => _revoke(
                                d.id,
                                d.name,
                                isPriority: true,
                              ),
                              icon: Icon(
                                Icons.lock_outline_rounded,
                                color: AppColors.danger.withValues(
                                  alpha: 0.55,
                                ),
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                if (session.devices.length > 1) ...[
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _loading ? null : _revokeAll,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: canRevokeAll
                          ? AppColors.danger
                          : AppColors.textSecondary,
                      side: BorderSide(
                        color: (canRevokeAll
                                ? AppColors.danger
                                : AppColors.textSecondary)
                            .withValues(alpha: 0.5),
                      ),
                    ),
                    child: Text(copy.revokeAllDevices),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RenameDeviceDialog extends StatefulWidget {
  const _RenameDeviceDialog({required this.initialName, required this.copy});

  final String initialName;
  final AppCopy copy;

  @override
  State<_RenameDeviceDialog> createState() => _RenameDeviceDialogState();
}

class _RenameDeviceDialogState extends State<_RenameDeviceDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF111622),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      title: Text(widget.copy.renameDevice),
      content: AppTextField(
        controller: _controller,
        label: widget.copy.deviceName,
        prefix: Icons.devices_rounded,
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(widget.copy.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.cyan,
            foregroundColor: Colors.black,
          ),
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: Text(widget.copy.save),
        ),
      ],
    );
  }
}
