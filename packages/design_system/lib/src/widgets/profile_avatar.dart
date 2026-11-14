import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Built-in profile avatars (client 20 Oct: selectable avatars / stickers
/// per profile). Drawn in the app's style; no third-party art. Stored on
/// the server's profile `avatarUrl` as `app:avatar/<key>`.
class ProfileAvatarStyle {
  const ProfileAvatarStyle(this.key, this.icon, this.colors) : asset = null;

  /// An illustrated face (client 9 Nov: "proper avatar images, not stickers").
  const ProfileAvatarStyle.face(this.key, this.colors)
      : icon = null,
        asset = 'assets/avatars/$key.png';

  final String key;
  final IconData? icon;
  final List<Color> colors;

  /// Picture in this package (`package: 'design_system'`), for faces.
  final String? asset;
  String get token => '$avatarTokenPrefix$key';
}

/// Illustrated profile pictures (point 37, 12 Nov): "Lorelei" by Lisa
/// Wischofsky via DiceBear, CC0 1.0 (assets/avatars/LICENSE.txt). The same
/// 30 pictures on LG / Samsung (`public/avatars/`). These are the ones the
/// pickers offer; the older icon avatars still show for profiles that have
/// one.
final kProfileFaces = <ProfileAvatarStyle>[
  for (final (i, c) in _faceBackgrounds.indexed)
    ProfileAvatarStyle.face('face${(i + 1).toString().padLeft(2, '0')}', c),
];

// Background of each face (its gradient), used while the picture loads.
final _faceBackgrounds = <List<Color>>[
  [AppColors.cyan, Color(0xFF0057FF)], [AppColors.match, Color(0xFF0E9F6E)],
  [Color(0xFF7C4DFF), Color(0xFF311B92)], [Color(0xFFFF8A65), Color(0xFFE64A19)],
  [Color(0xFF4DD0E1), Color(0xFF00838F)], [Color(0xFFF06292), Color(0xFFAD1457)],
  [AppColors.magenta, Color(0xFF8A2BE2)], [AppColors.gold, Color(0xFFF59E0B)],
  [AppColors.match, Color(0xFF0E9F6E)], [Color(0xFF7C4DFF), Color(0xFF311B92)],
  [Color(0xFFFF8A65), Color(0xFFE64A19)], [AppColors.cyan, Color(0xFF0057FF)],
  [AppColors.magenta, Color(0xFF8A2BE2)], [AppColors.match, Color(0xFF0E9F6E)],
  [Color(0xFFFF8A65), Color(0xFFE64A19)], [AppColors.cyan, Color(0xFF0057FF)],
  [AppColors.gold, Color(0xFFF59E0B)], [AppColors.match, Color(0xFF0E9F6E)],
  [Color(0xFF4DD0E1), Color(0xFF00838F)], [AppColors.gold, Color(0xFFF59E0B)],
  [Color(0xFF7C4DFF), Color(0xFF311B92)], [Color(0xFFFF8A65), Color(0xFFE64A19)],
  [Color(0xFF4DD0E1), Color(0xFF00838F)], [AppColors.cyan, Color(0xFF0057FF)],
  [AppColors.match, Color(0xFF0E9F6E)], [Color(0xFFF06292), Color(0xFFAD1457)],
  [Color(0xFFFF8A65), Color(0xFFE64A19)], [AppColors.cyan, Color(0xFF0057FF)],
  [Color(0xFFF06292), Color(0xFFAD1457)], [Color(0xFF4DD0E1), Color(0xFF00838F)],
];

const avatarTokenPrefix = 'app:avatar/';

/// What the avatar pickers offer (phone, iPhone, Android TV, Windows).
final kProfileAvatars = kProfileFaces;

/// The first avatars (icon on a gradient, 20–21 Oct). Not offered any more,
/// still drawn for profiles that chose one.
const kIconAvatars = <ProfileAvatarStyle>[
  ProfileAvatarStyle('neon', Icons.bolt_rounded, [Color(0xFF00D1FF), Color(0xFF0057FF)]),
  ProfileAvatarStyle('magenta', Icons.auto_awesome_rounded, [Color(0xFFFF4F9A), Color(0xFF8A2BE2)]),
  ProfileAvatarStyle('football', Icons.sports_soccer_rounded, [Color(0xFF22C55E), Color(0xFF065F46)]),
  ProfileAvatarStyle('cinema', Icons.movie_filter_rounded, [Color(0xFFF59E0B), Color(0xFFB45309)]),
  ProfileAvatarStyle('music', Icons.headphones_rounded, [Color(0xFFA855F7), Color(0xFF4C1D95)]),
  ProfileAvatarStyle('game', Icons.sports_esports_rounded, [Color(0xFF06B6D4), Color(0xFF155E75)]),
  ProfileAvatarStyle('star', Icons.star_rounded, [Color(0xFFFACC15), Color(0xFFCA8A04)]),
  ProfileAvatarStyle('rocket', Icons.rocket_launch_rounded, [Color(0xFFEF4444), Color(0xFF7F1D1D)]),
  ProfileAvatarStyle('pet', Icons.pets_rounded, [Color(0xFFFB923C), Color(0xFF9A3412)]),
  ProfileAvatarStyle('flower', Icons.local_florist_rounded, [Color(0xFFF472B6), Color(0xFF9D174D)]),
  ProfileAvatarStyle('moon', Icons.nightlight_round, [Color(0xFF6366F1), Color(0xFF1E1B4B)]),
  ProfileAvatarStyle('crown', Icons.workspace_premium_rounded, [Color(0xFFE5C07B), Color(0xFF8A6D2B)]),
  // Client 21 Oct A11: "try another sticker or smiles" — faces and characters.
  ProfileAvatarStyle('smile', Icons.sentiment_very_satisfied_rounded, [Color(0xFFFFD54F), Color(0xFFF57F17)]),
  ProfileAvatarStyle('happy', Icons.emoji_emotions_rounded, [Color(0xFF4DD0E1), Color(0xFF00838F)]),
  ProfileAvatarStyle('cool', Icons.face_6_rounded, [Color(0xFF7C4DFF), Color(0xFF311B92)]),
  ProfileAvatarStyle('kid', Icons.face_4_rounded, [Color(0xFFFF8A65), Color(0xFFBF360C)]),
  ProfileAvatarStyle('girl', Icons.face_3_rounded, [Color(0xFFF06292), Color(0xFF880E4F)]),
  ProfileAvatarStyle('boy', Icons.face_rounded, [Color(0xFF64B5F6), Color(0xFF0D47A1)]),
  ProfileAvatarStyle('baby', Icons.child_care_rounded, [Color(0xFFAED581), Color(0xFF33691E)]),
  ProfileAvatarStyle('robot', Icons.smart_toy_rounded, [Color(0xFF90A4AE), Color(0xFF263238)]),
  ProfileAvatarStyle('bunny', Icons.cruelty_free_rounded, [Color(0xFFF8BBD0), Color(0xFFAD1457)]),
  ProfileAvatarStyle('nature', Icons.emoji_nature_rounded, [Color(0xFF81C784), Color(0xFF1B5E20)]),
  ProfileAvatarStyle('icecream', Icons.icecream_rounded, [Color(0xFFFFAB91), Color(0xFFD84315)]),
  ProfileAvatarStyle('basketball', Icons.sports_basketball_rounded, [Color(0xFFFFB74D), Color(0xFFE65100)]),
];

ProfileAvatarStyle? avatarStyleFor(String? token) {
  final t = token ?? '';
  if (!t.startsWith(avatarTokenPrefix)) return null;
  final key = t.substring(avatarTokenPrefix.length);
  for (final s in kProfileFaces) {
    if (s.key == key) return s;
  }
  for (final s in kIconAvatars) {
    if (s.key == key) return s;
  }
  return null;
}

/// A profile's avatar: the chosen built-in style, else its initials.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.initials,
    this.token,
    this.size = 56,
    this.selected = false,
  });

  final String initials;
  final String? token;
  final double size;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final style = avatarStyleFor(token);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: style == null
            ? const LinearGradient(colors: [Color(0xFF1C2A40), Color(0xFF0F1726)])
            : LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: style.colors),
        border: Border.all(
          color: selected ? AppColors.cyan : Colors.white24,
          width: selected ? 3 : 1,
        ),
        boxShadow: selected ? [BoxShadow(color: AppColors.cyan.withValues(alpha: 0.5), blurRadius: 12)] : null,
      ),
      child: style == null
          ? Text(initials, style: TextStyle(fontSize: size * 0.38, fontWeight: FontWeight.w900, color: Colors.white))
          : style.asset != null
              ? ClipOval(child: avatarImage(style, size))
              : Icon(style.icon, size: size * 0.52, color: Colors.white),
    );
  }
}

/// Fills a TV profile tile: the chosen avatar (gradient + icon) or the
/// initials in the profile colour.
class ProfileAvatarFace extends StatelessWidget {
  const ProfileAvatarFace({
    super.key,
    required this.initials,
    required this.color,
    required this.fontSize,
    this.token,
    this.radius = 12,
  });

  final String initials;
  final String? token;
  final Color color;
  final double fontSize;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final style = avatarStyleFor(token);
    if (style == null) {
      return Center(
        child: Text(initials, style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w900, color: color)),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: style.colors),
      ),
      child: style.asset != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: SizedBox.expand(child: avatarImage(style, null)),
            )
          : Center(child: Icon(style.icon, size: fontSize * 1.5, color: Colors.white)),
    );
  }
}

/// The face picture of [style] (an icon avatar draws its icon instead),
/// sized to [size] or filling its parent.
Widget avatarImage(ProfileAvatarStyle style, double? size) {
  final asset = style.asset;
  if (asset == null) {
    return Icon(style.icon, size: (size ?? 48) * 0.52, color: Colors.white);
  }
  return Image.asset(
    asset,
    package: 'design_system',
    width: size,
    height: size,
    fit: BoxFit.cover,
    filterQuality: FilterQuality.medium,
    gaplessPlayback: true,
    errorBuilder: (_, _, _) => const SizedBox.shrink(),
  );
}
