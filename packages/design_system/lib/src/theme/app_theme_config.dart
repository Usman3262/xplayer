import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Global app theme — every colour in the app comes from here.
///
/// Today the values are the built-in XPlayer defaults ([AppThemeConfig.defaults]).
/// Later the admin panel (Supabase) sends a JSON theme; call
/// [AppThemeConfig.applyJson] with it (ideally before `runApp`). Unknown or
/// missing keys keep their default, so a partial theme is fine.
///
/// JSON format (all optional, colours as "#RRGGBB" or "#AARRGGBB"):
/// ```json
/// {
///   "background": "#0B0B12", "surface": "#14141F", "surfaceElevated": "#1C1C2B",
///   "primary": "#22D3EE", "primaryDim": "#06B6D4", "secondary": "#7C3AED",
///   "gold": "#FBBF24", "live": "#F43F5E", "success": "#34D399",
///   "textPrimary": "#F1F5F9", "textSecondary": "#94A3B8",
///   "border": "#2A2A3D", "danger": "#EF4444"
/// }
/// ```
@immutable
class AppThemeConfig {
  const AppThemeConfig({
    required this.background,
    required this.surface,
    required this.surfaceElevated,
    required this.primary,
    required this.primaryDim,
    required this.secondary,
    required this.gold,
    required this.live,
    required this.success,
    required this.textPrimary,
    required this.textSecondary,
    required this.border,
    required this.danger,
  });

  /// Screen background.
  final Color background;
  /// Cards, sheets.
  final Color surface;
  /// Raised cards, dialogs.
  final Color surfaceElevated;
  /// Main accent (buttons, focus, highlights).
  final Color primary;
  /// Darker main accent.
  final Color primaryDim;
  /// Second accent (gradients, badges).
  final Color secondary;
  /// Premium / rating accent.
  final Color gold;
  /// LIVE badges.
  final Color live;
  /// Positive / sports accent.
  final Color success;
  final Color textPrimary;
  final Color textSecondary;
  final Color border;
  final Color danger;

  /// Built-in XPlayer palette (violet + cyan on near-black).
  static const defaults = AppThemeConfig(
    background: Color(0xFF0B0B12),
    surface: Color(0xFF14141F),
    surfaceElevated: Color(0xFF1C1C2B),
    primary: Color(0xFF22D3EE),
    primaryDim: Color(0xFF06B6D4),
    secondary: Color(0xFF7C3AED),
    gold: Color(0xFFFBBF24),
    live: Color(0xFFF43F5E),
    success: Color(0xFF34D399),
    textPrimary: Color(0xFFF1F5F9),
    textSecondary: Color(0xFF94A3B8),
    border: Color(0xFF2A2A3D),
    danger: Color(0xFFEF4444),
  );

  static AppThemeConfig _current = defaults;

  /// The theme in use now.
  static AppThemeConfig get current => _current;

  /// Bumps every time the theme changes; the app root listens to it and
  /// rebuilds the whole widget tree.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// Switch to [config] app-wide.
  static void apply(AppThemeConfig config) {
    if (config == _current) return;
    _current = config;
    revision.value++;
  }

  /// Switch to a theme from JSON (e.g. the admin panel). Bad values are ignored.
  static void applyJson(Map<String, dynamic> json) =>
      apply(defaults.mergeJson(json));

  /// Back to the built-in theme.
  static void reset() => apply(defaults);

  /// A copy of this theme with any colours present in [json] replaced.
  AppThemeConfig mergeJson(Map<String, dynamic> json) {
    Color pick(String key, Color fallback) =>
        _parseColor(json[key]) ?? fallback;
    return AppThemeConfig(
      background: pick('background', background),
      surface: pick('surface', surface),
      surfaceElevated: pick('surfaceElevated', surfaceElevated),
      primary: pick('primary', primary),
      primaryDim: pick('primaryDim', primaryDim),
      secondary: pick('secondary', secondary),
      gold: pick('gold', gold),
      live: pick('live', live),
      success: pick('success', success),
      textPrimary: pick('textPrimary', textPrimary),
      textSecondary: pick('textSecondary', textSecondary),
      border: pick('border', border),
      danger: pick('danger', danger),
    );
  }

  Map<String, String> toJson() => {
        'background': _hex(background),
        'surface': _hex(surface),
        'surfaceElevated': _hex(surfaceElevated),
        'primary': _hex(primary),
        'primaryDim': _hex(primaryDim),
        'secondary': _hex(secondary),
        'gold': _hex(gold),
        'live': _hex(live),
        'success': _hex(success),
        'textPrimary': _hex(textPrimary),
        'textSecondary': _hex(textSecondary),
        'border': _hex(border),
        'danger': _hex(danger),
      };

  static Color? _parseColor(Object? v) {
    if (v is int) return Color(v);
    if (v is! String) return null;
    var s = v.trim().replaceFirst('#', '');
    if (s.length == 6) s = 'FF$s';
    if (s.length != 8) return null;
    final n = int.tryParse(s, radix: 16);
    return n == null ? null : Color(n);
  }

  static String _hex(Color c) =>
      '#${c.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';

  @override
  bool operator ==(Object other) =>
      other is AppThemeConfig &&
      other.background == background &&
      other.surface == surface &&
      other.surfaceElevated == surfaceElevated &&
      other.primary == primary &&
      other.primaryDim == primaryDim &&
      other.secondary == secondary &&
      other.gold == gold &&
      other.live == live &&
      other.success == success &&
      other.textPrimary == textPrimary &&
      other.textSecondary == textSecondary &&
      other.border == border &&
      other.danger == danger;

  @override
  int get hashCode => Object.hash(background, surface, surfaceElevated, primary,
      primaryDim, secondary, gold, live, success, textPrimary, textSecondary,
      border, danger);
}
