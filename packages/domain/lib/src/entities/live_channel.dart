import '../utils/display_name.dart';

class LiveChannel {
  const LiveChannel({
    required this.id,
    required this.name,
    required this.code,
    required this.nowTitle,
    required this.nextTitle,
    this.badge,
    this.progress = 0.5,
    this.progressLabel,
    this.accent = LiveAccent.cyan,
    this.isOnScreen = false,
    this.specs = const [],
    this.imageUrl,
    this.streamUrl,
  });

  final String id;
  final String name;
  final String code;

  String get displayName => cleanDisplayName(name, keepQuality: true);
  final String nowTitle;
  final String nextTitle;
  final String? badge;
  final double progress;
  final String? progressLabel;
  final LiveAccent accent;
  final bool isOnScreen;
  final List<String> specs;
  final String? imageUrl;
  final String? streamUrl;
}

enum LiveAccent { cyan, magenta }
