import 'package:data/data.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// Panel types offered on "Choose your panel": the admin's list (order,
/// on/off, label, description, help, icon, placeholders) when a config is
/// published, else the built-in three. Field labels stay in the app's
/// language (AppCopy); the admin texts are shown as given.
class PanelOption {
  const PanelOption({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.help,
    this.placeholders = const {},
  });

  final ProviderKind kind;
  final String title;
  final String subtitle;
  final IconData icon;
  final String? help;

  /// Field key (admin config keys: host/username/password, url/epg_url,
  /// portal/mac) → placeholder.
  final Map<String, String> placeholders;
}

List<PanelOption> panelOptions(RemoteConfig config, AppCopy copy) {
  final builtIn = {for (final o in _builtIn(copy)) o.kind: o};
  if (config.panelTypes.isEmpty) return builtIn.values.toList();
  final out = <PanelOption>[];
  for (final t in config.panelTypes) {
    final kind = ProviderKind.fromKey(t.key);
    final base = kind == null ? null : builtIn[kind];
    if (kind == null || base == null) continue; // a type this app can't speak yet
    out.add(PanelOption(
      kind: kind,
      title: t.label.trim().isEmpty ? base.title : t.label,
      subtitle: (t.description ?? '').trim().isEmpty ? base.subtitle : t.description!,
      icon: _icons[t.icon] ?? base.icon,
      help: (t.help ?? '').trim().isEmpty ? null : t.help,
      placeholders: {
        for (final f in t.fields)
          if ((f.placeholder ?? '').trim().isNotEmpty) f.key: f.placeholder!,
      },
    ));
  }
  return out;
}

List<PanelOption> _builtIn(AppCopy copy) => [
      PanelOption(kind: ProviderKind.xtream, title: copy.panelXtream, subtitle: copy.panelXtreamDesc, icon: Icons.dns_rounded),
      PanelOption(kind: ProviderKind.m3u, title: copy.panelM3u, subtitle: copy.panelM3uDesc, icon: Icons.playlist_play_rounded),
      PanelOption(kind: ProviderKind.stalker, title: copy.panelStalker, subtitle: copy.panelStalkerDesc, icon: Icons.router_rounded),
    ];

/// Admin icon names (Material names) → icons the app ships.
const _icons = <String, IconData>{
  'dns': Icons.dns_rounded,
  'playlist_play': Icons.playlist_play_rounded,
  'router': Icons.router_rounded,
  'live_tv': Icons.live_tv_rounded,
  'tv': Icons.tv_rounded,
  'link': Icons.link_rounded,
  'cloud': Icons.cloud_outlined,
};

/// User-facing message for a failed connect / check.
String panelFailureText(ProviderFailure f, AppCopy copy, {int maxPanels = 5}) => switch (f.kind) {
      ProviderFailureKind.unauthorized => copy.panelErrUnauthorized,
      ProviderFailureKind.expired => copy.panelErrExpired,
      ProviderFailureKind.banned => copy.panelErrBanned,
      ProviderFailureKind.network => copy.panelErrNetwork,
      ProviderFailureKind.timeout => copy.panelErrTimeout,
      ProviderFailureKind.rateLimited => copy.panelErrBusy,
      ProviderFailureKind.server => copy.panelErrServer,
      ProviderFailureKind.badResponse => copy.panelErrBadResponse,
      ProviderFailureKind.unsupported =>
        f.detail.endsWith(' off') ? copy.panelErrTypeOff : copy.panelErrUnsupported,
      ProviderFailureKind.invalidInput =>
        f.detail.startsWith('max panels') ? copy.panelErrTooMany(maxPanels) : copy.panelErrBadResponse,
    };

/// Short status label for a saved panel.
String panelStatusText(PanelConnection c, AppCopy copy) => switch (c.status) {
      ConnectionStatus.active || ConnectionStatus.connected || ConnectionStatus.synchronizing => copy.panelStatusActive,
      ConnectionStatus.expired => copy.panelStatusExpired,
      ConnectionStatus.unauthorized => copy.panelStatusRefused,
      ConnectionStatus.temporarilyUnavailable => copy.panelStatusUnreachable,
      ConnectionStatus.disabled || ConnectionStatus.removed => copy.panelStatusOff,
      ConnectionStatus.pending || ConnectionStatus.connecting => copy.panelStatusChecking,
      ConnectionStatus.invalidConfiguration => copy.panelStatusCheckDetails,
    };

/// Field-level message for a local validation problem.
String panelInputErrorText(ProviderInputError e, AppCopy copy) => switch (e) {
      ProviderInputError.required => copy.errFieldRequired,
      ProviderInputError.invalidUrl => copy.errInvalidUrl,
      ProviderInputError.invalidMac => copy.errInvalidMac,
    };
