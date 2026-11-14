import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'app_loaders.dart';

class AppLoading extends StatelessWidget {
  const AppLoading({super.key, this.label, this.auth = false});

  final String? label;
  final bool auth;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: auth
          ? AppLoader.auth(label: label)
          : AppLoader.page(label: label),
    );
  }
}

class AppEmpty extends StatelessWidget {
  const AppEmpty({
    super.key,
    required this.title,
    this.subtitle,
    this.icon = Icons.inbox_outlined,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.border),
              ),
              child: Icon(icon, color: AppColors.cyan, size: 34),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.cyan,
                ),
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Honest empty state when backend has no API yet.
class AppComingSoon extends StatelessWidget {
  const AppComingSoon({
    super.key,
    required this.title,
    this.subtitle =
        'This feature is coming soon. We will enable it when the API is ready.',
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return AppEmpty(
      title: title,
      subtitle: subtitle,
      icon: Icons.schedule_rounded,
    );
  }
}
