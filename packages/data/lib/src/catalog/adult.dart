import '../backend/remote_config.dart';

/// Decides which panel categories are adult (18+): the panel's own flag
/// (Xtream `is_adult`, Stalker `censored`) or a keyword in the category
/// name. Keywords come from the admin (`content.adult_keywords`); words match
/// whole words only, so "Sussex" / "Essex" are not "sex".
class AdultClassifier {
  AdultClassifier([List<String> keywords = defaultKeywords])
      : _patterns = [
          for (final k in keywords.map((k) => k.trim().toLowerCase()).where((k) => k.isNotEmpty)) _pattern(k),
        ];

  factory AdultClassifier.fromConfig(RemoteConfig c) =>
      AdultClassifier(c.listSetting('content.adult_keywords', defaultKeywords));

  static const defaultKeywords = [
    'xxx', 'adult', 'adults', '18+', '+18', 'porn', 'porno', 'sex', 'sexy', 'erotic', 'erotica',
    'hentai', 'playboy', 'hustler', 'brazzers', 'للكبار', 'كبار فقط',
  ];

  final List<RegExp> _patterns;

  /// Letters/digits around a word keyword mean it's part of another word.
  static RegExp _pattern(String k) {
    final escaped = RegExp.escape(k);
    final wordy = RegExp(r'^[\p{L}\p{N}]+$', unicode: true).hasMatch(k);
    return wordy
        ? RegExp('(^|[^\\p{L}\\p{N}])$escaped(\$|[^\\p{L}\\p{N}])', unicode: true, caseSensitive: false)
        : RegExp(escaped, caseSensitive: false);
  }

  bool isAdultName(String name) => _patterns.any((p) => p.hasMatch(name));

  bool isAdultCategory(String name, {bool panelFlag = false}) => panelFlag || isAdultName(name);
}
