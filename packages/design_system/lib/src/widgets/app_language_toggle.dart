import 'package:flutter/material.dart';

import '../locale/app_locale.dart';
import '../theme/app_colors.dart';

/// Compact EN | عربي language control. Cycles on tap; persists via [onChanged].
class AppLanguageToggle extends StatelessWidget {
  const AppLanguageToggle({
    super.key,
    required this.language,
    required this.onChanged,
    this.compact = true,
    /// App-bar style: icon + current language only (narrow).
    this.minimal = false,
  });

  final String language;
  final ValueChanged<String> onChanged;
  final bool compact;
  final bool minimal;

  @override
  Widget build(BuildContext context) {
    final lang = AppLocale.resolve(language);
    final current = switch (lang) {
      AppLang.en => 'EN',
      AppLang.ar => 'عربي',
      AppLang.ur => 'EN',
    };
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => onChanged(AppLocale.next(language)),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: minimal ? 8 : (compact ? 10 : 14),
              vertical: minimal ? 6 : (compact ? 7 : 10),
            ),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: minimal
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.language_rounded,
                        size: 16,
                        color: AppColors.cyan,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        current,
                        style: const TextStyle(
                          color: Color(0xFFCBD5E1),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.language_rounded,
                        size: compact ? 14 : 18,
                        color: AppColors.cyan,
                      ),
                      SizedBox(width: compact ? 6 : 8),
                      _LangLabel(
                        'EN',
                        selected: lang == AppLang.en,
                        compact: compact,
                      ),
                      _sep(compact),
                      _LangLabel(
                        'عربي',
                        selected: lang == AppLang.ar,
                        compact: compact,
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _sep(bool compact) => Text(
        ' | ',
        style: TextStyle(
          color: const Color(0xFF475569),
          fontSize: compact ? 11 : 12,
        ),
      );
}

class _LangLabel extends StatelessWidget {
  const _LangLabel(this.text, {required this.selected, required this.compact});

  final String text;
  final bool selected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: selected ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
        fontSize: compact ? 11 : 12,
        fontWeight: selected ? FontWeight.w800 : FontWeight.w400,
      ),
    );
  }
}
