/// Kids hub categories 
///
/// Match these against `GET /catalog/{vod|series|live}/categories` by
/// normalized name so new titles in those panel categories appear automatically.
abstract final class KidsPanelCategories {
  static const seriesNames = <String>[
    'رمضان أطفال 2026',
    'مسلسلات شاهد كيدز',
    'مسلسلات أطفال مترجمة',
    'مسلسلات أطفال مدبلجة',
    'مسلسلات أطفال إسلامية',
    'مسلسلات كرتون زمان',
    'مسلسلات أطفال مغربية',
    'مسلسلات أطفال تونسية',
    'مسلسلات كرتون للكبار مترجمة',
  ];

  static const movieNames = <String>[
    'أفلام أطفال فائقة الوضوح 4K',
    'أفلام أطفال مترجمة',
    'أفلام أطفال مدبلجة',
  ];

  static const liveNames = <String>[
    'أطفال (Kids)',
    'Kids LQ أطفال',
  ];

  /// All panel labels in chip order (series → movies → live).
  static List<String> get allNames => [
        ...seriesNames,
        ...movieNames,
        ...liveNames,
      ];

  /// Loose match: trim, collapse spaces, case-fold Latin bits; allow contains.
  static bool matches(String panelName, String apiName) {
    final a = _key(panelName);
    final b = _key(apiName);
    if (a.isEmpty || b.isEmpty) return false;
    if (a == b) return true;

    final aCore = _stripParens(a);
    final bCore = _stripParens(b);
    if (aCore.isNotEmpty && aCore == bCore) return true;

    // Near-match when one label embeds the other (emoji / LQ tags).
    if (a.length >= 6 && b.length >= 6 && (a.contains(b) || b.contains(a))) {
      return true;
    }
    if (aCore.length >= 6 &&
        bCore.length >= 6 &&
        (aCore.contains(bCore) || bCore.contains(aCore))) {
      return true;
    }
    return false;
  }

  static String _stripParens(String s) =>
      s.replaceAll(RegExp(r'\([^)]*\)'), '').replaceAll(RegExp(r'\s+'), ' ').trim();

  static String _key(String s) {
    return s
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .toLowerCase();
  }

  /// Any provider category that is clearly for children (client 20 Oct:
  /// Kids showed only fixed names, missed "KIDS أطفال" with 92 channels and
  /// any category the provider adds later).
  static bool looksKids(String apiName) {
    final n = _key(apiName);
    const words = ['أطفال', 'اطفال', 'كيدز', 'كرتون', 'kids', 'kid ', 'cartoon', 'toon', 'junior', 'baby'];
    return words.any(n.contains);
  }

  /// True when [apiName] is one of the Kids panel category names for [kind].
  static bool isKidsCategory(String apiName, {required String kind}) {
    final list = switch (kind) {
      'series' => seriesNames,
      'vod' || 'movie' => movieNames,
      'live' => liveNames,
      _ => const <String>[],
    };
    return list.any((n) => matches(n, apiName));
  }
}
