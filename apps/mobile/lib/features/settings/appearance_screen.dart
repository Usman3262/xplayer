import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/appearance_controller.dart';
import '../../core/session_controller.dart';
import '../../widgets/main_app_bar.dart';

class AppearanceScreen extends ConsumerStatefulWidget {
  const AppearanceScreen({super.key});

  @override
  ConsumerState<AppearanceScreen> createState() => _AppearanceScreenState();
}

class _AppearanceScreenState extends ConsumerState<AppearanceScreen> {
  int selected = 0;
  int depth = 0;
  bool neonGlow = true;
  bool reducedMotion = false;
  bool _seeded = false;

  @override
  Widget build(BuildContext context) {
    final appearance = ref.watch(appearanceProvider);
    if (appearance.loaded && !_seeded) {
      _seeded = true;
      selected = appearance.preset;
      depth = appearance.depth;
      neonGlow = appearance.neonGlow;
      reducedMotion = appearance.reducedMotion;
    }

    final copy = AppCopy.ofLanguage(
      ref.watch(sessionProvider.select((s) => s.language)),
    );
    final themes = copy.appearanceThemesList;

    final preview = AppearanceState(
      preset: selected,
      depth: depth,
      neonGlow: neonGlow,
      reducedMotion: reducedMotion,
      loaded: true,
    );
    final accents = preview.accents;

    return Scaffold(
      appBar: const MainAppBar(showBack: true),
      body: AppAtmosphere(
        intensity: preview.atmosphereIntensity,
        cyanAccent: accents.$1,
        magentaAccent: accents.$2,
        background: accents.$3,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Row(
              children: [
                Text(
                  copy.appearanceThemes,
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22),
                ),
                const Spacer(),
                TechBadge(copy.livePreview),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              copy.chooseThemeHint,
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            // C26: three glass theme previews (client asked before full themes).
            SectionHeader(title: copy.curatedThemes),
            const SizedBox(height: 10),
            SizedBox(
              height: 108,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: themes.length.clamp(0, 3),
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (_, i) {
                  final on = selected == i;
                  final sample = AppearanceState(
                    preset: i,
                    depth: depth,
                    neonGlow: neonGlow,
                    reducedMotion: reducedMotion,
                    loaded: true,
                  ).accents;
                  return InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () async {
                      setState(() => selected = i);
                      await ref.read(appearanceProvider.notifier).save(
                            preset: i,
                            depth: depth,
                            neonGlow: neonGlow,
                            reducedMotion: reducedMotion,
                          );
                    },
                    child: Container(
                      width: 132,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            sample.$1.withValues(alpha: 0.35),
                            sample.$3,
                            sample.$2.withValues(alpha: 0.28),
                          ],
                        ),
                        border: Border.all(
                          color: on ? sample.$1 : Colors.white24,
                          width: on ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            themes[i].$1,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                          const Spacer(),
                          Row(
                            children: [
                              _swatch(sample.$1),
                              const SizedBox(width: 4),
                              _swatch(sample.$2),
                              const SizedBox(width: 4),
                              _swatch(sample.$3),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            ...List.generate(themes.length, (i) {
              final t = themes[i];
              final on = selected == i;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () async {
                      setState(() => selected = i);
                      // Apply immediately so color changes are not "Apply-only".
                      await ref.read(appearanceProvider.notifier).save(
                            preset: i,
                            depth: depth,
                            neonGlow: neonGlow,
                            reducedMotion: reducedMotion,
                          );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.surface.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: on ? accents.$1 : AppColors.border,
                          width: on ? 1.6 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            on
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            color: on ? accents.$1 : AppColors.textSecondary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  t.$1,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  t.$2,
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(height: 12),
            SectionHeader(title: copy.depth),
            Slider(
              value: depth.toDouble(),
              min: 0,
              max: 2,
              divisions: 2,
              label: [
                copy.depthSoft,
                copy.depthBalanced,
                copy.depthStrong,
              ][depth.clamp(0, 2)],
              activeColor: accents.$1,
              onChanged: (v) async {
                final next = v.round();
                setState(() => depth = next);
                await ref.read(appearanceProvider.notifier).save(
                      preset: selected,
                      depth: next,
                      neonGlow: neonGlow,
                      reducedMotion: reducedMotion,
                    );
              },
            ),
            SwitchListTile(
              title: Text(copy.neonGlow),
              value: neonGlow,
              activeThumbColor: accents.$1,
              onChanged: (v) async {
                setState(() => neonGlow = v);
                await ref.read(appearanceProvider.notifier).save(
                      preset: selected,
                      depth: depth,
                      neonGlow: v,
                      reducedMotion: reducedMotion,
                    );
              },
            ),
            SwitchListTile(
              title: Text(copy.reduceMotion),
              value: reducedMotion,
              activeThumbColor: accents.$1,
              onChanged: (v) async {
                setState(() => reducedMotion = v);
                await ref.read(appearanceProvider.notifier).save(
                      preset: selected,
                      depth: depth,
                      neonGlow: neonGlow,
                      reducedMotion: v,
                    );
              },
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: copy.applyThemeSave,
              icon: Icons.check_rounded,
              onPressed: () async {
                await ref.read(appearanceProvider.notifier).save(
                      preset: selected,
                      depth: depth,
                      neonGlow: neonGlow,
                      reducedMotion: reducedMotion,
                    );
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(copy.themeApplied)),
                );
                Navigator.of(context).maybePop();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _swatch(Color c) => Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: c,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24),
        ),
      );
}
