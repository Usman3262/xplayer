import 'dart:ui';

import 'package:data/data.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/account.dart';
import '../../core/app_log.dart';
import '../../core/panels.dart';
import '../../core/remote_config.dart';
import '../../core/session_controller.dart';
import '../auth/login_screen.dart' show LoginField, LoginFieldLabel, LoginGlow, LoginRoundIconBtn;
import 'panel_copy.dart';

/// Panel login form (Xtream / M3U / Stalker) → Connect. Local checks first
/// (instant), then one login call; the panel is saved only if it works.
class PanelFormScreen extends ConsumerStatefulWidget {
  const PanelFormScreen({super.key, required this.kind});

  final ProviderKind kind;

  @override
  ConsumerState<PanelFormScreen> createState() => _PanelFormScreenState();
}

class _PanelFormScreenState extends ConsumerState<PanelFormScreen> {
  final _a = TextEditingController(); // host / url / portal
  final _b = TextEditingController(); // username / epg url / mac
  final _c = TextEditingController(); // password
  final _name = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;
  Map<String, ProviderInputError> _fieldErrors = const {};
  String? _deviceMac;

  @override
  void initState() {
    super.initState();
    if (widget.kind == ProviderKind.stalker) {
      PanelsService.manager.deviceMac().then((mac) {
        if (!mounted) return;
        setState(() {
          _deviceMac = mac;
          if (_b.text.isEmpty) _b.text = mac;
        });
      });
    }
  }

  @override
  void dispose() {
    for (final c in [_a, _b, _c, _name]) {
      c.dispose();
    }
    super.dispose();
  }

  ProviderCredentials get _credentials => switch (widget.kind) {
        ProviderKind.xtream => XtreamCredentials(server: _a.text, username: _b.text, password: _c.text),
        ProviderKind.m3u => M3uCredentials(url: _a.text, epgUrl: _b.text.trim().isEmpty ? null : _b.text.trim()),
        ProviderKind.stalker => StalkerCredentials(portal: _a.text, mac: _b.text),
      };

  Future<void> _connect(AppCopy copy) async {
    if (_busy) return;
    final creds = _credentials;
    final problems = creds.validate();
    setState(() {
      _fieldErrors = problems;
      _error = null;
    });
    if (problems.isNotEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    AppLog.tap('connect.submit', data: {'kind': widget.kind.name});
    final manager = PanelsService.manager;
    final wasFirst = !PanelsService.hasPanel;
    try {
      await manager.connect(creds, name: _name.text);
      if (!mounted) return;
      final offer = wasFirst && await AccountService.shouldOffer(ref.read(accountPolicyProvider));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(copy.panelConnected)));
      // First panel → (one-time account offer) → Home. Router sends "account
      // required" users to sign-in by itself.
      context.go(!wasFirst ? '/settings/panels' : (offer ? '/account-offer' : '/home'));
    } on ProviderFailure catch (f) {
      AppLog.info('Connect', 'failed: ${f.kind.name}'); // no URL / credentials
      if (mounted) setState(() => _error = panelFailureText(f, copy, maxPanels: manager.maxPanels));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _err(String key, AppCopy copy) {
    final e = _fieldErrors[key];
    return e == null ? null : panelInputErrorText(e, copy);
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppCopy.ofLanguage(ref.watch(panelUiLanguageProvider));
    final option = panelOptions(ref.watch(remoteConfigProvider), copy)
        .where((o) => o.kind == widget.kind)
        .firstOrNull;
    final ph = option?.placeholders ?? const <String, String>{};

    final fields = <Widget>[
      ...switch (widget.kind) {
        ProviderKind.xtream => [
            LoginFieldLabel(copy.fieldServerUrl),
            const SizedBox(height: 6),
            LoginField(
              controller: _a,
              hint: ph['host'] ?? 'http://example.com:8080',
              prefix: Icons.dns_outlined,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.next,
              errorText: _err('server', copy),
            ),
            const SizedBox(height: 14),
            LoginFieldLabel(copy.fieldUsername),
            const SizedBox(height: 6),
            LoginField(
              controller: _b,
              hint: ph['username'],
              prefix: Icons.person_outline_rounded,
              textInputAction: TextInputAction.next,
              errorText: _err('username', copy),
            ),
            const SizedBox(height: 14),
            LoginFieldLabel(copy.fieldPassword),
            const SizedBox(height: 6),
            LoginField(
              controller: _c,
              obscure: _obscure,
              prefix: Icons.lock_outline_rounded,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _connect(copy),
              errorText: _err('password', copy),
              suffix: IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(
                  _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ProviderKind.m3u => [
            LoginFieldLabel(copy.fieldPlaylistUrl),
            const SizedBox(height: 6),
            LoginField(
              controller: _a,
              hint: ph['url'] ?? 'http://example.com/playlist.m3u',
              prefix: Icons.link_rounded,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.next,
              errorText: _err('url', copy),
            ),
            const SizedBox(height: 14),
            LoginFieldLabel(copy.fieldEpgUrl),
            const SizedBox(height: 6),
            LoginField(
              controller: _b,
              hint: ph['epg_url'] ?? 'http://example.com/epg.xml',
              prefix: Icons.event_note_outlined,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _connect(copy),
              errorText: _err('epgUrl', copy),
            ),
          ],
        ProviderKind.stalker => [
            LoginFieldLabel(copy.fieldPortalUrl),
            const SizedBox(height: 6),
            LoginField(
              controller: _a,
              hint: ph['portal'] ?? 'http://example.com/c/',
              prefix: Icons.router_outlined,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.next,
              errorText: _err('portal', copy),
            ),
            const SizedBox(height: 14),
            LoginFieldLabel(copy.fieldMac),
            const SizedBox(height: 6),
            LoginField(
              controller: _b,
              hint: ph['mac'] ?? '00:1A:79:00:00:00',
              prefix: Icons.memory_rounded,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _connect(copy),
              errorText: _err('mac', copy),
              suffix: IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: copy.macCopied,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _b.text.trim()));
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(copy.macCopied)));
                },
                icon: Icon(Icons.copy_rounded, size: 18, color: AppColors.textSecondary),
              ),
            ),
            if (_deviceMac != null) ...[
              const SizedBox(height: 8),
              Text(copy.macDeviceHint, style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.4)),
            ],
          ],
      },
      const SizedBox(height: 14),
      LoginFieldLabel(copy.fieldPanelName),
      const SizedBox(height: 6),
      LoginField(controller: _name, hint: option?.title, prefix: Icons.label_outline_rounded),
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const LoginGlow(),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    children: [
                      LoginRoundIconBtn(
                        icon: const AppBackIcon(size: 18, style: AppBackIconStyle.chevron),
                        onTap: () => context.canPop() ? context.pop() : context.go('/connect'),
                      ),
                      const Spacer(),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const Center(child: AppLogo(height: 44, alignToStart: false)),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                            decoration: BoxDecoration(
                              color: AppColors.surface.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  option?.title ?? copy.choosePanelTitle,
                                  style: TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 24,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.6,
                                    height: 1.2,
                                  ),
                                ),
                                if ((option?.help ?? option?.subtitle) != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    option!.help ?? option.subtitle,
                                    style: TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.4),
                                  ),
                                ],
                                const SizedBox(height: 20),
                                ...fields,
                                if (_error != null) ...[
                                  const SizedBox(height: 12),
                                  Text(_error!, style: TextStyle(color: AppColors.danger, fontSize: 12, height: 1.4)),
                                ],
                                const SizedBox(height: 18),
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [
                                      BoxShadow(color: AppColors.primary.withValues(alpha: 0.35), blurRadius: 12),
                                    ],
                                  ),
                                  child: SizedBox(
                                    height: 52,
                                    child: FilledButton(
                                      key: const Key('panel-connect'),
                                      onPressed: _busy ? null : () => _connect(copy),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: AppColors.primary,
                                        foregroundColor: AppColors.textPrimary,
                                        disabledBackgroundColor: AppColors.primary,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
                                      child: _busy
                                          ? Center(child: AppLoader.button())
                                          : Text(
                                              copy.connectPanel,
                                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                                            ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
