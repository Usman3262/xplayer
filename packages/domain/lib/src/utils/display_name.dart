import '../entities/media_item.dart';
/// Cleans provider/catalog titles for customer-facing display.
/// Strips leading ### markers, language prefixes like `AR:`, and extra junk.
///
/// [keepQuality] (live channels, client 31 Oct): the provider's quality label
/// stays in the name ("MBC 1 RAW", "MBC 1 HD", "beIN 4K 3840p"); only the
/// decoration around it goes ("#####", "▼", "8K"). The 16 Oct request was to
/// remove those symbols, not RAW / HD: without the label the 1080p and SD
/// versions of a channel had the same name. Same rule as LG `cleanName`.
String cleanDisplayName(String raw, {bool keepQuality = false}) {
  var s = _plainSuperscripts(raw).trim();
  if (s.isEmpty) return s;

  if (keepQuality) {
    // Superscript tags come out lower case or split ("ᶠᴴᴰ" → "fHD").
    s = s.replaceAllMapped(
      RegExp(r'\b(?:f\s*hd|uhd|hd|sd|raw|hevc)\b', caseSensitive: false),
      (m) => m[0]!.replaceAll(RegExp(r'\s'), '').toUpperCase(),
    );
    // Client 12 Nov: live names lose 4K / 8K (and their pixel counts) and
    // keep HD / SD / RAW.
    s = s.replaceAll(RegExp(r'\b[48]\s*K\b', caseSensitive: false), ' ');
    s = s.replaceAll(RegExp(r'\b(?:4320|3840|2160)\s*p\b', caseSensitive: false), ' ');
  } else {
    // Provider marketing tokens (client 16 Oct #10): RAW feed tags and pixel
    // counts like 3840p ("BEIN SPORTS ⁸ᴷ ᴿᴬᵂ", "beIN ⁴ᴷ ³⁸⁴⁰ᵖ").
    s = s.replaceAll(RegExp(r'\bRAW\b', caseSensitive: false), ' ');
    s = s.replaceAll(RegExp(r'\b(?:4320|3840|2160)\s*p\b', caseSensitive: false), ' ');
  }
  // Invisible marks the provider leaves before a code ("ِِAR-AS: …").
  s = s.replaceFirst(_leadingMarks, '');

  // Leading hash banners: ###, #### Title, etc. A single "#" joined to a
  // word is part of the title ("#Alive", "#NoFilter").
  s = s.replaceFirst(_hashBanner, '');
  // Trailing / mid package hash noise: ##### TITLE #####
  s = s.replaceAll(RegExp(r'#{2,}'), ' ');

  // Explicit language / package prefixes: AR:, 4K-AR:, SUBS:, F:, BE:, 8K:
  s = s.replaceFirst(
    RegExp(
      r'^(?:4[Kk]-|8[Kk]-|HD-|SD-|LQ-)?(?:AR|EN|SUBS|F|BE|8[Kk]|HEVC|LQ|SD|HD|UHD)\s*[:\-|]\s*',
      caseSensitive: false,
    ),
    '',
  );
  // Provider region / language / section codes (client 16 Oct: "remove
  // AR, EG, SUB… from titles"): "EG: صقر", "SHAM: …", "IN-S: …",
  // "DOC-S: TYSON (2026) (US)". Known codes only, so real titles such as
  // "CSI: Miami" or "UFC: 300" keep their prefix. The code is kept as a
  // tag by [providerTitleTags].
  for (var i = 0; i < 2; i++) {
    s = s.replaceFirst(_providerPrefix, '');
  }
  // Client 12 Nov: every other provider code too, and new ones without an
  // app update ("PTV:", "ANM-S:", "AS-S-D:", "DSC+D:"). Real titles keep
  // theirs ("CSI: Miami", "BAKI-DOU: …", "Dune: Part Two").
  for (var i = 0; i < 3; i++) {
    final next = _stripProviderCode(s);
    if (next == s) break;
    s = next;
  }
  s = s.replaceFirst(_leadingMarks, '');
  s = s.replaceFirst(_trailingCountry, '');
  s = s.replaceAll(_subTokens, ' ');
  // Repeated prefix pass (e.g. "4K-AR: AR: Title")
  s = s.replaceFirst(
    RegExp(
      r'^(?:AR|EN|SUBS|F|BE)\s*:\s*',
      caseSensitive: false,
    ),
    '',
  );

  // Bracketed / pipe language tags often used by providers
  s = s.replaceAll(
    RegExp(r'[\[\(\|{]\s*AR\s*[\]\)|}]', caseSensitive: false),
    '',
  );
  // replaceAllMapped: Dart's replaceAll does not fill in "$1" (a live
  // channel showed as "FRANCE 24$1$2LQ").
  s = s.replaceAllMapped(
    RegExp(r'(^|[\s\-_|/])AR([\s\-_|/]|$)', caseSensitive: false),
    (m) => '${m[1]}${m[2]}',
  );

  // Client ask: strip soccer / promo glyphs from category & channel titles.
  s = s.replaceAll(
    RegExp(
      r'[\u26BD\u26BE\u{1F3C0}-\u{1F3C5}\u{1F3C8}\u{1F3C9}\u{1F945}\u{1F3CF}]',
      unicode: true,
    ),
    '',
  );
  // Decorative symbols in provider names (client 16 Oct #10): ⭐ ● ★ 🔥 …
  s = s.replaceAll(RegExp(r'[\p{So}\p{Sk}\u2022\u25CF]', unicode: true), ' ');
  // Mid-name marketing "8K" (keep real 4K/UHD).
  s = s.replaceAll(RegExp(r'\b8\s*K\b', caseSensitive: false), ' ');
  // Trailing provider suffixes like " BE" / "-BE" / "|BE".
  s = s.replaceFirst(
    RegExp(r'[\s\-_|/]*\bBE\b\s*$', caseSensitive: false),
    '',
  );

  // Client 27 Oct #11 (same as LG / Samsung): quality / source prefixes
  // ("CAM:", "FHD |", "TOP -", "NEW:"), quality words at the end, and
  // stray marks around the title.
  for (var i = 0; i < 2; i++) {
    s = s.replaceFirst(_sourcePrefix, '');
  }
  if (!keepQuality) {
    s = s.replaceAll(_bracketQuality, ' ');
    s = s.replaceFirst(_trailingQuality, '');
  }
  s = s.replaceAll(RegExp(r'[|•●★☆✪✦✧◆◇■□▶►◀◄⚡🔥⭐]+'), ' ');

  // Trailing/leading separators left by stripping
  s = s.replaceAll(RegExp(r'^[\s\-_|/:]+|[\s\-_|/:]+$'), '');
  s = s.replaceAll(RegExp(r'\s{2,}'), ' ');
  return s.trim();
}

final _hashBanner = RegExp(r'^(?:#{2,}\s*|#\s+|#$)+');
final _sourcePrefix = RegExp(
  r'^(?:CAM|TS|HDCAM|WEB|WEBRIP|WEB-DL|BLURAY|FHD|UHD|HD|SD|4K|8K|HEVC|H265|TOP|NEW|VIP|PREMIUM|EXCLUSIVE)\s*[:|\-–]\s*',
  caseSensitive: false,
);
final _bracketQuality = RegExp(
  r'\s*[\[(](?:FHD|UHD|HD|SD|4K|8K|HEVC|H\.?265|CAM|MULTI|DUAL|AUDIO|SUB|SUBS|DUB)[\])]\s*',
  caseSensitive: false,
);
final _trailingQuality = RegExp(
  r'(?:\s+[|\-–]\s*|\s+)(?:FHD|UHD|HEVC|H\.?265|CAM)\s*$',
  caseSensitive: false,
);
final _leadingMarks = RegExp(
  r'^[\u064B-\u065F\u0670\u200B-\u200F\u202A-\u202E\u2066-\u2069\uFEFF\s]+',
);

// ---------------------------------------------------------------------------
// Provider codes before a title (client 12 Nov: "remove all other provider
// prefixes … and automatically remove any new provider prefixes").
//
// Catalog scan 12 Nov 2026 (10,053 series, 14,644 films): every code in use
// is in [_knownCodes]. A code that is not listed is still removed when it
// looks like the provider's: capital letters joined to a known code or a
// one-letter marker ("XYZ-S:", "XYZ-D:"), or 2–4 capitals before a title in
// the provider's style (Arabic text, "(2026)", "(US)"). Real titles that
// start with capitals keep them ([_protectedPrefixes]).
// Same rule in LG / Samsung `core/names.ts`; keep them in step.
// ---------------------------------------------------------------------------

const _knownCodes = {
  'AR', 'EN', 'EG', 'SY', 'LB', 'IQ', 'IRQ', 'KH', 'GULF', 'SHAM', 'MA', 'TN',
  'DZ', 'ALG', 'LY', 'YE', 'JOR', 'PSE', 'TR', 'IN', 'PK', 'AF', 'KR', 'AS',
  'ASIA', 'AI', 'FR', 'DE', 'ES', 'NL', 'PT', 'RU', 'US', 'UK', 'GB', 'DOC',
  'DSC', 'GEO', 'SUB', 'SUBS', 'SUBBS', 'SUIBS', 'SIBS', 'DUB', 'ISL', 'CH',
  'KIDS', 'KID', 'KD', 'ANM', 'XMAS', 'NF', 'NETFLIX', 'OSN', 'SHAHID', 'TOD',
  'STAR', 'STC', 'VIP', 'MULTI', 'PTV', 'POD', 'BDY', 'HARA', 'FW', 'SHR',
  'MS', 'ST', 'ART', 'CAM', 'D',
};

/// One-letter (and "UP") markers joined to a code: S = series, D = dubbed,
/// E, M, F, "S-UP".
const _codeMarkers = {'S', 'D', 'M', 'F', 'E', 'UP'};

/// Capitals that start real titles ("CSI: Miami", "IT: Welcome to Derry").
const _protectedPrefixes = {
  'CSI', 'NCIS', 'FBI', 'CIA', 'SWAT', 'UFC', 'WWE', 'WWF', 'AEW', 'NXT',
  'NBA', 'NFL', 'NHL', 'MLB', 'MMA', 'DC', 'LEGO', 'TMNT', 'JAG', 'ER', 'MASH',
  'BBC', 'CNN', 'HBO', 'NASA', 'XXX', 'SAS', 'LOL', 'TRON', 'DOOM', 'BTS',
  'DOTA', 'ARK', 'ID', 'IT', 'UFO', 'SOS', 'USA', 'PAW', 'RRR', 'AKA', 'DNA',
  'UHF', 'NYPD', 'LAPD', 'JFK', 'ALF', 'KISS', 'ABBA', 'WALL', 'X-MEN',
};

final _codeGroup = RegExp(
  r'^([A-Z]{1,7}(?:\s*[-+]\s*[A-Z]{1,7}){0,3}|[A-Z]{2,7}\s+[A-Z]{2,7})\s*[:|]\s*',
);
final _arabicLetter = RegExp(r'[\u0600-\u06FF]');
final _yearInBrackets = RegExp(r'\((?:19|20)\d{2}\)');

List<String> _codeParts(String group) =>
    group.split(RegExp(r'[\s+\-]+')).where((p) => p.isNotEmpty).toList();

bool _isProviderCode(String group, String rest) {
  final parts = _codeParts(group);
  if (parts.isEmpty) return false;
  final joined = parts.join('-');
  if (_protectedPrefixes.contains(joined) ||
      _protectedPrefixes.contains(parts.first)) {
    return false;
  }
  if (parts.length == 1) {
    final p = parts.first;
    if (_knownCodes.contains(p)) return true;
    if (p.length < 2 || p.length > 4) return false;
    return _arabicLetter.hasMatch(rest) ||
        _yearInBrackets.hasMatch(rest) ||
        _trailingCountry.hasMatch(rest);
  }
  // "AR KH": two codes with a space, both known.
  if (!group.contains('-') && !group.contains('+')) {
    return parts.every(_knownCodes.contains);
  }
  // "TR-D", "AS-S-S", "DSC+D", "PTV-SUBS", "S-UP"; not "BAKI-DOU".
  return parts.any((p) => _knownCodes.contains(p) || _codeMarkers.contains(p));
}

String _stripProviderCode(String s) {
  final m = _codeGroup.firstMatch(s);
  if (m == null) return s;
  final rest = s.substring(m.end);
  if (rest.trim().isEmpty) return s;
  return _isProviderCode(m.group(1)!, rest) ? rest : s;
}

/// Badge for dubbed titles: «مدبلج» in Arabic, "Dubbed" in English (client
/// 12 Nov: "TR-D, IN-D, DUB" and every other dubbed code).
const dubbedBadge = 'DUBBED';

final _dubToken = RegExp(r'(?<![\w-])(?:DUB|DUBBED)(?![\w-])', caseSensitive: false);

/// True when the provider marks the title as dubbed: a "-D" code ("TR-D:",
/// "AS-S-D:", "DSC+D:"), "DUB" / "DUBBED". Not when the title already says
/// «مدبلج» (no second label).
bool isDubbedTitle(String? raw) {
  if (raw == null || raw.isEmpty) return false;
  if (raw.contains('مدبلج')) return false;
  var s = _plainSuperscripts(raw).trim().replaceFirst(_leadingMarks, '');
  s = s.replaceFirst(RegExp(r'^(?:#+\s*)+'), '');
  for (var i = 0; i < 3; i++) {
    final m = _codeGroup.firstMatch(s);
    if (m == null) break;
    final rest = s.substring(m.end);
    final parts = _codeParts(m.group(1)!);
    if (!_isProviderCode(m.group(1)!, rest)) break;
    if (parts.length > 1 && parts.contains('D')) return true;
    if (parts.contains('DUB') || parts.contains('DUBBED')) return true;
    s = rest;
  }
  return _dubToken.hasMatch(raw);
}

const _providerCodes =
    'AR|EN|EG|SY|LB|IQ|KH|GULF|SHAM|MA|TN|DZ|TR|IN|PK|AF|KR|AS|ASIA|FR|DE|ES|NL|PT|RU|US|UK|DOC|SUB|SUBS|SUBBS|DUB|ISL|CH|KIDS|XMAS|NF|NETFLIX|OSN|SHAHID|TOD|STAR|VIP|MULTI';
// "EG: …", "AR-DE: …", "AR-IN-S: …", "EG - …": one to three known codes
// joined by "-", then ":" / "|" (or a spaced dash).
final _providerPrefix = RegExp(
  '^((?:$_providerCodes)(?:-(?:$_providerCodes|S|M|F)){0,2})'
  r'(?:\s*[:|]\s*|\s+[-\u2013]\s+)',
  caseSensitive: false,
);
final _trailingCountry = RegExp(r'\s*\((?:US|UK|GB|FR|DE|ES|IT|IN|KR|TR|EG|CA|AU|JP|CN)\)\s*$');
final _subTokens = RegExp(r'(?<![\w-])(?:SUBS?|DUBBED|DUB|MULTI-SUB)(?![\w-])', caseSensitive: false);
final _subOnly = RegExp(r'(?<![\w-])(?:SUBS?|MULTI-SUB)(?![\w-])', caseSensitive: false);

/// Provider tags taken out of a title by [cleanDisplayName], for a small
/// badge instead of title clutter: the region / section code ("EG", "DE",
/// "IN", "DOC"), not "AR" (the app is Arabic-first) or the "-S" series
/// marker, plus "SUB" for subtitled releases.
List<String> providerTitleTags(String raw) {
  final s = _plainSuperscripts(raw).trim().replaceFirst(RegExp(r'^(?:#+\s*)+'), '');
  final tags = <String>[];
  if (isDubbedTitle(raw)) tags.add(dubbedBadge);
  final m = _providerPrefix.matchAsPrefix(s);
  if (m != null) {
    for (final part in m.group(1)!.toUpperCase().split('-')) {
      final code = (part == 'SUBS' || part == 'SUBBS') ? 'SUB' : part;
      if (code == 'AR' || code == 'S' || code == 'M' || code == 'F') continue;
      // Shown as the Dubbed badge instead.
      if (code == 'DUB' || code == 'D') continue;
      if (!tags.contains(code)) tags.add(code);
    }
  }
  if (_subOnly.hasMatch(s) && !tags.contains('SUB')) tags.add('SUB');
  return tags.take(tags.contains(dubbedBadge) ? 3 : 2).toList();
}

final RegExp _resellerAdRe = RegExp(
  r'(whats\s*app|wh?atsapp|watsap|telegram|t\.me/|https?://|www\.|'
  r'\.(?:com|net|org|xyz|online|shop|store)\b|@[a-z0-9_]{3,}|'
  r'\bsubscri(?:be|ption)\b|\brenew(?:al)?\b|\breseller\b|\bcontact\b|'
  r'\biptv\s*(?:server|panel|code|subscription)\b|\bserver\s*(?:code|panel|info)\b|'
  r'واتس|واتساب|تلجرام|تيليجرام|اشتراك|للاشتراك|تجديد|للتواصل|تواصل\s*معنا|اتصل|'
  r'سيرفر|كود\s*تفعيل|للطلب|اطلب)',
  caseSensitive: false,
);

// 8+ digit runs (optionally +, spaces or dashes): phone numbers in ad rows.
final RegExp _phoneRe = RegExp(r'(?:\+?\d[\d\s\-]{7,}\d)');

/// Provider package headers / server ad slots (##### banners, empty junk).
/// Also drops promo / ad / "8K" marketing rows the client asked to hide.
bool isProviderAdOrHeaderChannel(String name, {String? rawName}) {
  final candidates = <String>[
    name,
    if (rawName != null && rawName.isNotEmpty) rawName,
  ];
  for (final c in candidates) {
    final t = c.trim();
    if (t.contains('#####')) return true;
    // "### Package Name ###", "=== ALWAN ===", "*** PROMO ***": a name
    // wrapped in banner marks is a package header, not a channel.
    if (RegExp(r'^\s*([#=*~_\-])\1{2,}.*\1{3,}\s*$').hasMatch(t)) return true;
    if (RegExp(r'^#+\s*$').hasMatch(t)) return true;
    if (RegExp(r'^#{2,}').hasMatch(t) && cleanDisplayName(t).isEmpty) {
      return true;
    }
    final lower = t.toLowerCase();
    // Server promo / ad slots often titled like these.
    if (RegExp(
      r'(server\s*ads?|promo\s*channel|\bpromotional\b|advert(?:isement)?|trailer\s*ad|\bad\s*slot\b)',
      caseSensitive: false,
    ).hasMatch(lower)) {
      return true;
    }
    // Reseller adverts placed as channels: contact numbers, WhatsApp /
    // Telegram handles, web links and "subscribe / renew" offers
    // (client 31 Oct, testers saw server adverts in the channel lists).
    if (_resellerAdRe.hasMatch(t) || _phoneRe.hasMatch(t)) return true;
    // Standalone "8K" / "8K PACKAGE" marketing labels — check raw first
    // (cleanDisplayName strips mid-name 8K for normal titles).
    if (RegExp(
      r'^(?:\[?\s*8\s*k\s*\]?|8k(?:\s*(?:promo|ad|banner|package|uhd)?)?)\s*$',
      caseSensitive: false,
    ).hasMatch(t)) {
      return true;
    }
    final cleaned = cleanDisplayName(t);
    if (RegExp(r'^8\s*k(\s|$|[:\-_|])', caseSensitive: false).hasMatch(t) &&
        cleaned.length < 10) {
      return true;
    }
    // Symbols / punctuation only. Not `\W`: in Dart (without `unicode`)
    // every non-Latin letter is `\W`, so each all-Arabic channel name
    // ("قناة الجزيرة", "شاهد") was dropped as an ad row, and packages of
    // Arabic channels showed as empty (client 17 Oct "categories showing
    // zero").
    if (cleaned.isEmpty ||
        RegExp(r'^[\p{P}\p{S}\p{Z}_]+$', unicode: true).hasMatch(cleaned)) {
      return true;
    }
  }
  return cleanDisplayName(name).isEmpty;
}


/// Provider names use Unicode superscripts as styling ("ᴴᴰ", "⁸ᴷ", "ᴿᴬᵂ").
/// Map them to plain letters so the token rules above can see them; any
/// other superscript / modifier symbol is dropped.
String _plainSuperscripts(String s) {
  const map = {
    '⁰': '0', '¹': '1', '²': '2', '³': '3', '⁴': '4', '⁵': '5', '⁶': '6',
    '⁷': '7', '⁸': '8', '⁹': '9',
    'ᴬ': 'A', 'ᴮ': 'B', 'ᴰ': 'D', 'ᴱ': 'E', 'ᴳ': 'G', 'ᴴ': 'H', 'ᴵ': 'I',
    'ᴶ': 'J', 'ᴷ': 'K', 'ᴸ': 'L', 'ᴹ': 'M', 'ᴺ': 'N', 'ᴼ': 'O', 'ᴾ': 'P',
    'ᴿ': 'R', 'ᵀ': 'T', 'ᵁ': 'U', 'ⱽ': 'V', 'ᵂ': 'W',
    'ᵃ': 'a', 'ᵇ': 'b', 'ᶜ': 'c', 'ᵈ': 'd', 'ᵉ': 'e', 'ᶠ': 'f', 'ᵍ': 'g',
    'ʰ': 'h', 'ⁱ': 'i', 'ʲ': 'j', 'ᵏ': 'k', 'ˡ': 'l', 'ᵐ': 'm', 'ⁿ': 'n',
    'ᵒ': 'o', 'ᵖ': 'p', 'ʳ': 'r', 'ˢ': 's', 'ᵗ': 't', 'ᵘ': 'u', 'ᵛ': 'v',
    'ʷ': 'w', 'ˣ': 'x', 'ʸ': 'y', 'ᶻ': 'z',
    '⁽': '(', '⁾': ')',
  };
  final out = StringBuffer();
  var prevSup = false;
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    final plain = map[ch];
    final isSup = plain != null ||
        (r >= 0x2070 && r <= 0x209F) ||
        (r >= 0x1D2C && r <= 0x1DBF) ||
        (r >= 0x02B0 && r <= 0x02FF);
    if (isSup) {
      // Separate a superscript run from the word before it ("F1ᴴᴰ").
      if (!prevSup) out.write(' ');
      if (plain != null) out.write(plain);
      prevSup = true;
    } else {
      if (prevSup && ch.trim().isNotEmpty) out.write(' ');
      out.write(ch);
      prevSup = false;
    }
  }
  return out.toString();
}

/// Tag on titles that are not released yet (client 4 Nov, as on LG): they
/// show "Soon" and no Watch Now / Download.
const soonBadge = 'SOON';
final _upcoming = RegExp(r'قريب(?:ا|اً|ًا|آ)(?![ء-ي])|coming\s*soon', caseSensitive: false);

/// "قريبا" / "coming soon" in the provider's name, as the backend's
/// `isUpcomingTitle` and LG (the tatweel in "قــريباً" is ignored).
bool isUpcomingTitle(String? raw) =>
    raw != null && _upcoming.hasMatch(raw.replaceAll('ـ', ''));

extension MediaItemSoon on MediaItem {
  bool get isUpcoming => badges.contains(soonBadge);
}

/// Client 5 Nov #9: the Thmanyah Blue package ("THMANYAH ●" / 🔵) starts with
/// an advertising channel; it is dropped on every platform.
bool isPackageWithLeadingAd(String? packageName) {
  final n = (packageName ?? '').toLowerCase();
  final thmanyah = n.contains('thmanyah') || n.contains('thamanya') || n.contains('ثمانية');
  final blue = n.contains('blue') || n.contains('●') || n.contains('🔵') || n.contains('أزرق') || n.contains('ازرق');
  return thmanyah && blue;
}
