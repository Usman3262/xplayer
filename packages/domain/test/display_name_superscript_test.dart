import 'package:domain/domain.dart';
import 'package:test/test.dart';

void main() {
  test('superscript provider tags become plain or are removed', () {
    expect(cleanDisplayName('BEIN SPORTS ⁸ᴷ ᴿᴬᵂ'), 'BEIN SPORTS');
    expect(cleanDisplayName('BEIN SPORTS ⁸ᴷ SD'), 'BEIN SPORTS SD');
    expect(cleanDisplayName('ALWAN SPORT ᴿᴬᵂ'), 'ALWAN SPORT');
    expect(cleanDisplayName('ALWAN F1 ᴴᴰ'), 'ALWAN F1 HD');
    expect(cleanDisplayName('SOLO SPORT ᴮᴱ'), 'SOLO SPORT');
    expect(cleanDisplayName('beIN ⁴ᴷ ³⁸⁴⁰ᵖ (EVENT ONLY)'), 'beIN 4K (EVENT ONLY)');
  });

  test('decorative symbols are removed', () {
    expect(cleanDisplayName('STC EXCLUSIVE HD ⭐'), 'STC EXCLUSIVE HD');
    expect(cleanDisplayName('THMANYAH ●'), 'THMANYAH');
    expect(cleanDisplayName('قنوات رياضية ★'), 'قنوات رياضية');
  });

  test('normal titles are unchanged', () {
    expect(cleanDisplayName('MBC 1 HD'), 'MBC 1 HD');
    expect(cleanDisplayName('beIN SPORTS 1 SD'), 'beIN SPORTS 1 SD');
    expect(cleanDisplayName('Rawhide (1959)'), 'Rawhide (1959)');
  });

  test('provider region/language prefixes leave titles, kept as tags', () {
    expect(cleanDisplayName('EG: صقر وكناريا'), 'صقر وكناريا');
    expect(providerTitleTags('EG: صقر وكناريا'), ['EG']);
    expect(cleanDisplayName('DOC-S: TYSON (2026) (US)'), 'TYSON (2026)');
    expect(cleanDisplayName('SUBS: VisionQuest (2026) (US)'), 'VisionQuest (2026)');
    expect(providerTitleTags('SUBS: VisionQuest (2026)'), ['SUB']);
    expect(cleanDisplayName('IN-S: THANAL (2025)'), 'THANAL (2025)');
    // Real titles with a colon keep it.
    expect(cleanDisplayName('AR-IN-S: Aakhree Raasta (1986)'), 'Aakhree Raasta (1986)');
    expect(providerTitleTags('AR-IN-S: Aakhree Raasta (1986)'), ['IN']);
    expect(cleanDisplayName('AR-DE: Animals (2026)'), 'Animals (2026)');
    expect(providerTitleTags('AR-DE: Animals (2026)'), ['DE']);
    expect(providerTitleTags('AR-EG: صقر وكناريا'), ['EG']);
    expect(cleanDisplayName('EG - القصص'), 'القصص');
    expect(cleanDisplayName('SUBBS: VisionQuest (2026)'), 'VisionQuest (2026)');
    expect(providerTitleTags('SUBBS: VisionQuest (2026)'), ['SUB']);
    expect(cleanDisplayName('CSI: Miami'), 'CSI: Miami');
    expect(cleanDisplayName('UFC: 300'), 'UFC: 300');
  });

  test('banner-wrapped package names are headers, not channels', () {
    expect(isProviderAdOrHeaderChannel('### ALWAN SPORT ###'), isTrue);
    expect(isProviderAdOrHeaderChannel('=== PROMO ==='), isTrue);
    expect(isProviderAdOrHeaderChannel('beIN SPORTS 1 HD'), isFalse);
  });
}
