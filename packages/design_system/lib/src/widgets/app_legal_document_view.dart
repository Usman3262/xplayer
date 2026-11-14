import 'package:flutter/material.dart';

import '../legal/app_legal_copy.dart';
import '../locale/app_locale.dart';
import '../theme/app_colors.dart';

/// Scrollable legal document (Privacy / Terms) with section cards + copyright.
class AppLegalDocumentView extends StatelessWidget {
  const AppLegalDocumentView({
    super.key,
    required this.title,
    required this.sections,
    this.footer,
    this.copyright,
  });

  final String title;
  final List<({String title, String body})> sections;
  final String? footer;
  final String? copyright;

  factory AppLegalDocumentView.privacy({
    Key? key,
    AppLang lang = AppLang.en,
  }) {
    return AppLegalDocumentView(
      key: key,
      title: AppLegalCopy.privacyTitle(lang),
      sections: AppLegalCopy.privacySections(lang),
      footer: AppLegalCopy.privacyLastUpdated(lang),
      copyright: AppLegalCopy.copyright(lang),
    );
  }

  factory AppLegalDocumentView.terms({
    Key? key,
    AppLang lang = AppLang.en,
  }) {
    return AppLegalDocumentView(
      key: key,
      title: AppLegalCopy.termsTitle(lang),
      sections: AppLegalCopy.termsSections(lang),
      copyright: AppLegalCopy.copyright(lang),
    );
  }

  @override
  Widget build(BuildContext context) {
    final footCopyright = copyright ?? AppLegalCopy.copyright(AppLang.en);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 22,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 16),
        for (final section in sections) ...[
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  section.title,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  section.body,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    height: 1.45,
                    fontSize: 13.5,
                  ),
                ),
              ],
            ),
          ),
        ],
        if (footer != null) ...[
          const SizedBox(height: 8),
          Text(
            footer!,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textSecondary.withValues(alpha: 0.8),
              fontSize: 12,
            ),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          footCopyright,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
