import 'package:data/data.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tv_locale.dart';
import '../../core/tv_session.dart';
import '../../widgets/focus_tile.dart';
import '../../widgets/tv_action_feedback.dart';
import 'tv_security_scaffold.dart';

class TvDevicesScreen extends ConsumerStatefulWidget {
  const TvDevicesScreen({super.key});

  @override
  ConsumerState<TvDevicesScreen> createState() => _TvDevicesScreenState();
}

class _TvDevicesScreenState extends ConsumerState<TvDevicesScreen> {
  bool _loading = true;
  String? _error;
  List<DeviceDto> _devices = const [];
  String? _thisId;

  AppCopy get _copy => AppCopy.ofLanguage(ref.read(tvLanguageProvider));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final auth = ref.read(tvAuthRepositoryProvider);
      final list = await auth.listDevices();
      final thisId = await auth.thisDeviceId();
      if (!mounted) return;
      setState(() {
        _devices =
            list.where((d) => d.status.toUpperCase() == 'ACTIVE').toList();
        _thisId = thisId;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      await ref.read(tvSessionProvider.notifier).handleAuthLoss(e);
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _rename(DeviceDto d) async {
    final copy = _copy;
    final controller = TextEditingController(text: d.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111622),
        title: Text(copy.renameDevice),
        content: AppTextField(
          controller: controller,
          label: copy.deviceName,
          prefix: Icons.devices_rounded,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(copy.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.cyan,
              foregroundColor: Colors.black,
            ),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(copy.save),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || name == d.name) return;
    try {
      await ref
          .read(tvAuthRepositoryProvider)
          .renameDevice(deviceId: d.id, name: name);
      await _load();
      if (!mounted) return;
      await TvActionFeedback.success(
        context,
        title: copy.deviceRenamed,
        message: copy.deviceLabelUpdated,
      );
    } catch (e) {
      if (!mounted) return;
      await TvActionFeedback.error(
        context,
        title: copy.renameFailed,
        message: TvActionFeedback.clean(e),
      );
    }
  }

  Future<void> _revokeAll() async {
    final copy = _copy;
    final hasPriority = _devices.any((d) => d.isPriority);
    final iAmPriority = _devices.any(
      (d) => d.isPriority && (d.isCurrent || d.id == _thisId),
    );
    if (!DeviceTrustPolicy.canRevokeAll(
      actorIsPriority: iAmPriority,
      accountHasPriority: hasPriority,
    )) {
      await TvActionFeedback.error(
        context,
        title: copy.cannotRevokeAllWithoutPrimaryTitle,
        message: copy.cannotRevokeAllWithoutPrimaryBody,
      );
      return;
    }
    final ok = await TvActionFeedback.confirm(
      context,
      title: copy.revokeAllDevicesTitle,
      message: copy.revokeAllDevicesMessage,
      confirmLabel: copy.revokeAllDevices,
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(tvAuthRepositoryProvider).revokeAllDevices();
      await _load();
      if (!mounted) return;
      TvActionFeedback.toast(
        context,
        tone: AppAlertTone.success,
        title: copy.revokeAllDone,
        message: copy.revokeAllDevicesMessage,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      await TvActionFeedback.error(
        context,
        title: e.isPriorityRequired
            ? copy.cannotRevokeAllWithoutPrimaryTitle
            : copy.revokeFailed,
        message: e.isPriorityRequired
            ? copy.cannotRevokeAllWithoutPrimaryBody
            : TvActionFeedback.clean(e),
      );
    } catch (e) {
      if (!mounted) return;
      await TvActionFeedback.error(
        context,
        title: copy.revokeFailed,
        message: TvActionFeedback.clean(e),
      );
    }
  }

  Future<void> _revoke(DeviceDto d) async {
    final copy = _copy;
    if (!DeviceTrustPolicy.canRevokeDevice(targetIsPriority: d.isPriority)) {
      await TvActionFeedback.error(
        context,
        title: copy.cannotRevokePrimaryTitle,
        message: copy.cannotRevokePrimaryBody,
      );
      return;
    }
    final ok = await TvActionFeedback.confirm(
      context,
      title: copy.revokeThisDevice,
      message: copy.revokeDeviceMessage(d.name),
      confirmLabel: copy.revoke,
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(tvAuthRepositoryProvider).revokeDevice(
            d.id,
            targetIsPriority: d.isPriority,
          );
      await _load();
      if (!mounted) return;
      TvActionFeedback.toast(
        context,
        tone: AppAlertTone.success,
        title: copy.deviceRevoked,
        message: copy.deviceNoLongerLinked(d.name),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      await TvActionFeedback.error(
        context,
        title: e.isPriorityRequired
            ? copy.cannotRevokePrimaryTitle
            : copy.revokeFailed,
        message: e.isPriorityRequired
            ? copy.cannotRevokePrimaryBody
            : TvActionFeedback.clean(e),
      );
    } catch (e) {
      if (!mounted) return;
      await TvActionFeedback.error(
        context,
        title: copy.revokeFailed,
        message: TvActionFeedback.clean(e),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppCopy.ofLanguage(ref.watch(tvLanguageProvider));
    return TvSecurityScaffold(
      title: copy.devices,
      subtitle: copy.devicesRegisteredHint,
      helpBody: copy.devicesHelpBody(
        TvPlatformProfile.pc ? copy.thisPcWord : copy.thisTvWord,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                copy.devicesCount(_devices.length),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              if (_loading)
                AppLoader.inline(size: 18)
              else
                FocusTile(
                  borderRadius: 10,
                  onTap: _load,
                  child: Icon(
                    Icons.refresh_rounded,
                    color: AppColors.cyan,
                  ),
                ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: AppColors.danger)),
          ],
          const SizedBox(height: 12),
          Expanded(
            child: ListView.separated(
              itemCount: _devices.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final d = _devices[i];
                final mine = d.isCurrent || d.id == _thisId;
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0C101A),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        d.platform.toUpperCase().contains('TV')
                            ? Icons.tv_rounded
                            : Icons.smartphone_rounded,
                        color: AppColors.cyan,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              d.name,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            Text(
                              _deviceMetaLine(d),
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 6,
                              children: [
                                if (mine)
                                  TechBadge(copy.thisDevice, compact: true),
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
                      FocusTile(
                        borderRadius: 10,
                        onTap: () => _rename(d),
                        child: Icon(
                          Icons.edit_rounded,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      if (!mine)
                        FocusTile(
                          borderRadius: 10,
                          onTap: () => _revoke(d),
                          child: Icon(
                            d.isPriority
                                ? Icons.lock_outline_rounded
                                : Icons.link_off_rounded,
                            color: AppColors.danger.withValues(
                              alpha: d.isPriority ? 0.55 : 1,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          if (_devices.length > 1) ...[
            const SizedBox(height: 10),
            FocusTile(
              borderRadius: 12,
              onTap: _revokeAll,
              child: Container(
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.danger.withValues(alpha: 0.5),
                  ),
                ),
                child: Text(
                  copy.revokeAllDevices,
                  style: TextStyle(
                    color: AppColors.danger,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _deviceMetaLine(DeviceDto d) {
    final joined = _prettyDeviceTime(d.createdAt);
    final last = _prettyDeviceTime(d.lastSeenAt);
    final bits = <String>[d.platform];
    if (joined != null) bits.add('Joined $joined');
    if (last != null) bits.add('Last active $last');
    if (bits.length == 1) bits.add(d.status);
    return bits.join(' · ');
  }

  static String? _prettyDeviceTime(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return iso;
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 2) return 'Now';
    if (diff.inHours < 1) return '${diff.inMinutes} min ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 14) return '${diff.inDays}d ago';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}
