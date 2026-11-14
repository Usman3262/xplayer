/// Customer-facing titles: strip ### banners, AR language tags, extra junk.
String cleanDisplayName(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return s;

  s = s.replaceFirst(RegExp(r'^(?:#+\s*)+'), '');
  s = s.replaceAll(RegExp(r'#{2,}'), ' ');

  s = s.replaceFirst(
    RegExp(
      r'^(?:4[Kk]-|8[Kk]-|HD-|SD-|LQ-)?(?:AR|EN|SUBS|F|BE|8[Kk]|HEVC|LQ|SD|HD|UHD)\s*[:\-|]\s*',
      caseSensitive: false,
    ),
    '',
  );
  s = s.replaceFirst(
    RegExp(r'^(?:AR|EN|SUBS|F|BE)\s*:\s*', caseSensitive: false),
    '',
  );

  s = s.replaceAll(
    RegExp(r'[\[\(\|{]\s*AR\s*[\]\)|}]', caseSensitive: false),
    '',
  );
  s = s.replaceAll(
    RegExp(r'(^|[\s\-_|/])AR([\s\-_|/]|$)', caseSensitive: false),
    r'$1$2',
  );

  s = s.replaceAll(
    RegExp(
      r'[\u26BD\u26BE\u{1F3C0}-\u{1F3C5}\u{1F3C8}\u{1F3C9}\u{1F945}\u{1F3CF}]',
      unicode: true,
    ),
    '',
  );
  s = s.replaceAll(RegExp(r'\b8\s*K\b', caseSensitive: false), ' ');
  s = s.replaceFirst(
    RegExp(r'[\s\-_|/]*\bBE\b\s*$', caseSensitive: false),
    '',
  );

  s = s.replaceAll(RegExp(r'^[\s\-_|/:]+|[\s\-_|/:]+$'), '');
  s = s.replaceAll(RegExp(r'\s{2,}'), ' ');
  return s.trim();
}
