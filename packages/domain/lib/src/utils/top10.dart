import '../entities/media_item.dart';
import 'display_name.dart';

/// Top 10 Movies / Series, the same titles in the same order on every
/// platform (client 10–11 Nov: the same film twice, and a different list on
/// each device).
///
/// No ranking comes from the backend, so the list is the best-rated of the
/// newest titles:
/// 1. [newest] is the provider's 60 newest titles added before this week's
///    start ([weekStart], Friday 00:00 Saudi time), newest first; the list
///    stays the same all week and changes by itself every Friday;
/// 2. Coming Soon titles, titles without a poster and titles in
///    [excludeCategoryIds] (Kids) are left out;
/// 3. highest rating first, the newer title first on a tie;
/// 4. one title per name ([titleKey]): the provider lists the same film more
///    than once (language / quality versions, "TR-D: …");
/// 5. the first [count].
///
/// Nothing rotates and nothing is saved on the device, so every device that
/// gets the same newest list shows the same Top 10. LG / Samsung use the same
/// rule (`platforms/*/src/screens/Home.tsx`, `top10`); keep them in step.
abstract final class Top10 {
  static const count = 10;

  /// How many of the newest titles (added before [weekStart]) are ranked.
  static const poolSize = 60;

  /// Start of the current Top 10 / banner week: Friday 00:00 Saudi time
  /// (UTC+3, no daylight saving), i.e. Thursday 21:00 UTC (client 12 Nov:
  /// "every Friday, Saudi time"). Titles added after it wait for next week.
  static DateTime weekStart(DateTime now) {
    final saudi = now.toUtc().add(const Duration(hours: 3));
    final daysSinceFriday = (saudi.weekday - DateTime.friday) % 7;
    final fridayMidnightSaudi = DateTime.utc(saudi.year, saudi.month, saudi.day)
        .subtract(Duration(days: daysSinceFriday));
    return fridayMidnightSaudi.subtract(const Duration(hours: 3));
  }

  /// True when a title added at [addedSec] (Unix seconds) belongs to the
  /// week that started at [weekStart]. A title without a date counts.
  static bool addedBefore(int? addedSec, DateTime weekStart) =>
      addedSec == null ||
      addedSec < weekStart.millisecondsSinceEpoch ~/ 1000;

  static List<MediaItem> pick(
    List<MediaItem> newest, {
    Set<String> excludeCategoryIds = const {},
    DateTime? weekStart,
  }) {
    // This week's list: the [poolSize] newest titles added before the
    // week's start (newest first), so it does not change until Friday.
    final ranked = weekStart == null
        ? newest
        : newest
            .where((m) => addedBefore(m.addedSec, weekStart))
            .take(poolSize)
            .toList();
    final pool = <(int, MediaItem)>[];
    for (var i = 0; i < ranked.length; i++) {
      final m = ranked[i];
      if (m.isUpcoming) continue;
      if ((m.posterUrl ?? '').trim().isEmpty) continue;
      final cat = m.categoryId;
      if (cat != null && excludeCategoryIds.contains(cat)) continue;
      pool.add((i, m));
    }
    pool.sort((a, b) {
      final r = (b.$2.rating ?? 0).compareTo(a.$2.rating ?? 0);
      return r != 0 ? r : a.$1.compareTo(b.$1);
    });
    final seen = <String>{};
    final out = <MediaItem>[];
    for (final (_, m) in pool) {
      final key = titleKey(m.title);
      if (key.isNotEmpty && !seen.add(key)) continue;
      out.add(m);
      if (out.length == count) break;
    }
    return out;
  }

  static final _tag = RegExp(r'^\s*[a-z0-9]{1,4}(?:[-_][a-z0-9]{1,3})?\s*[:|]\s*');
  static final _brackets = RegExp(r'\([^)]*\)|\[[^\]]*\]');
  static final _year = RegExp(r'\b(?:19|20)\d{2}\b');
  static final _quality = RegExp(
    r'\b(?:4k|8k|uhd|fhd|hd|sd|hevc|h265|x265|multi|subs?|dub|dubbed)\b',
  );
  static final _nonWord = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

  /// The name two versions of one title share: lower case, without provider
  /// tags ("TR-D:", "AR:"), brackets, years, quality words or punctuation.
  static String titleKey(String title) {
    var s = title.toLowerCase();
    for (var i = 0; i < 3; i++) {
      final next = s.replaceFirst(_tag, '');
      if (next == s) break;
      s = next;
    }
    s = s
        .replaceAll(_brackets, ' ')
        .replaceAll(_year, ' ')
        .replaceAll(_quality, ' ')
        .replaceAll(_nonWord, ' ')
        .trim();
    return s;
  }
}
