import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'remote_image.dart';

/// Provider cast is one string: names separated by commas, Arabic commas or
/// runs of spaces ("محمد إمام  شيكو  خالد الصاوي"). No photos come with it.
List<String> parseCastNames(String? raw) {
  final v = (raw ?? '').trim();
  if (v.isEmpty) return const [];
  final parts = v.split(RegExp(r'\s*[,،;/|]\s*|\s{2,}'));
  final seen = <String>{};
  return [
    for (final p in parts)
      if (p.trim().isNotEmpty && seen.add(p.trim().toLowerCase())) p.trim(),
  ];
}

/// Cast row content: the TMDB list (names + photos) when there is one,
/// otherwise the provider's names without photos.
({List<String> names, List<String?>? photos}) castRow(
  String? providerNames,
  List<({String name, String? photoUrl})> withPhotos,
) {
  if (withPhotos.any((c) => (c.photoUrl ?? '').isNotEmpty)) {
    return (
      names: [for (final c in withPhotos) c.name],
      photos: [for (final c in withPhotos) c.photoUrl],
    );
  }
  return (names: parseCastNames(providerNames), photos: null);
}

/// One actor: photo in a circle (TMDB, client 23 Oct) or the initial + name.
class CastCard extends StatelessWidget {
  const CastCard({super.key, required this.name, this.photoUrl, this.scale = 1, this.focused = false});
  final String name;
  final String? photoUrl;
  final double scale;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final initial = name.characters.isEmpty ? '?' : name.characters.first.toUpperCase();
    return SizedBox(
      width: 96 * scale,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64 * scale,
            height: 64 * scale,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(colors: [Color(0xFF1C2A40), Color(0xFF0F1726)]),
              border: Border.all(color: focused ? AppColors.cyan : AppColors.border, width: focused ? 2.5 : 1),
            ),
            clipBehavior: Clip.antiAlias,
            child: (photoUrl ?? '').isNotEmpty
                ? RemoteImage(url: photoUrl, width: 64 * scale, height: 64 * scale, fit: BoxFit.cover)
                : Text(initial, style: TextStyle(fontSize: 26 * scale, fontWeight: FontWeight.w900, color: AppColors.cyan)),
          ),
          SizedBox(height: 8 * scale),
          Text(name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12 * scale, fontWeight: FontWeight.w700, height: 1.2)),
        ],
      ),
    );
  }
}

/// Horizontal row of [CastCard]s (phone details).
class CastStrip extends StatelessWidget {
  const CastStrip({super.key, required this.names, this.photos, this.scale = 1});
  final List<String> names;

  /// Photo per [names] index (same length), or null for initials only.
  final List<String?>? photos;
  final double scale;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 118 * scale,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: names.length,
          separatorBuilder: (_, _) => SizedBox(width: 10 * scale),
          itemBuilder: (_, i) => CastCard(
            name: names[i],
            photoUrl: photos != null && i < photos!.length ? photos![i] : null,
            scale: scale,
          ),
        ),
      );
}
