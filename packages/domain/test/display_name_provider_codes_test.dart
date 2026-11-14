import 'package:domain/domain.dart';
import 'package:test/test.dart';

// Client 12 Nov: every provider code leaves the title (also new ones), and
// dubbed titles get «مدبلج» / "Dubbed". Titles from the catalog scan of
// 12 Nov 2026 (10,053 series, 14,644 films).
void main() {
  group('provider codes leave the title', () {
    final cases = {
      'TR-D: اسطنبول راسا على عقب': 'اسطنبول راسا على عقب',
      'IN-D: لا احد سواك': 'لا احد سواك',
      'ANM-S: The World\'s Strongest Witch (2026) (JP)': 'The World\'s Strongest Witch (2026)',
      'AS-S: When I Meet the Moon (2026) (CN)': 'When I Meet the Moon (2026)',
      'AS-S-S: عودة المنبوذ لقيادة العاصفة': 'عودة المنبوذ لقيادة العاصفة',
      'AI-S-D: الجد الملياردير يتسول': 'الجد الملياردير يتسول',
      'PTV: ضيفي مع معتز الدمرداش': 'ضيفي مع معتز الدمرداش',
      'POD: بودكاست ايكولوجيا': 'بودكاست ايكولوجيا',
      'DOC-D: باور: مونديال': 'باور: مونديال',
      'DSC+D: The Last Woodsmen (2024) اخر الحطابين': 'The Last Woodsmen (2024) اخر الحطابين',
      'PTV-SUBS: Squid Game: The Challenge (2023) (GB)': 'Squid Game: The Challenge (2023)',
      'AR KH: جزيرة الضباب': 'جزيرة الضباب',
      'S-UP: هاي فايف: جمال رمزي': 'هاي فايف: جمال رمزي',
      'ST-E: يوم الكرامة': 'يوم الكرامة',
      'D: WWE Crown Jewel (2025)': 'WWE Crown Jewel (2025)',
      'ALG: Predator': 'Predator',
      'CAM: 7 Dogs (2026) الكلاب السبعة': '7 Dogs (2026) الكلاب السبعة',
      'SUIBS: Anaesthesia (2026) (PL)': 'Anaesthesia (2026) (PL)',
      'ِِAR-AS: Anecdotes of Ape Mountain (2026)': 'Anecdotes of Ape Mountain (2026)',
      'DUB - Kong: King of the Apes (2016) (CA) كونج: ملك القردة': 'Kong: King of the Apes (2016) (CA) كونج: ملك القردة',
      'ANM-D: BAKI-DOU: The Invincible Samurai (2026) (JP)': 'BAKI-DOU: The Invincible Samurai (2026)',
      // A code the app has never seen, in the provider's style.
      'QWE: مسلسل جديد': 'مسلسل جديد',
      'ZZ-S: New Show (2026) (US)': 'New Show (2026)',
      '4K: خرزة زرقا': 'خرزة زرقا',
    };
    cases.forEach((raw, want) {
      test(raw, () => expect(cleanDisplayName(raw), want));
    });
  });

  group('real titles keep their start', () {
    for (final t in [
      'CSI: Miami',
      'NCIS: Los Angeles (2009)',
      'FBI: Most Wanted (2020)',
      'IT: Welcome to Derry (2025)',
      'SAS: Red Notice (2021)',
      'XXX: Return of Xander Cage (2017)',
      'X-MEN: Apocalypse (2016)',
      'Dune: Part Two (2024)',
      '007: Tomorrow Never Dies (1997)',
      '9-1-1: Lone Star (2020)',
      'Lulwah: The Princess of Desert (2022) لولوة اميرة الصحراء',
      'طالع نازل: الحب اللي كان',
      '6:07 بيروت',
      'TRON: Ares (2025)',
      'UFC: 300',
    ]) {
      test(t, () => expect(cleanDisplayName(t), cleanDisplayName(cleanDisplayName(t))));
      test('$t keeps its first word', () {
        final first = t.split(RegExp(r'[:\s]')).first;
        expect(cleanDisplayName(t), startsWith(first));
      });
    }
  });

  group('dubbed', () {
    for (final raw in [
      'TR-D: اسطنبول راسا على عقب',
      'IN-D: Ikka (2026)',
      'AS-D: Agent Kim Reactivated (2026) (KR)',
      'ANM-S-D: سيدتي ماذا فعلت بخادم الشيطان؟',
      'DSC+D: The Last Woodsmen (2024)',
      'DUB: Grand Hotel (2024) الفندق الملعون',
      'DUB - Kong: King of the Apes (2016)',
      'Some Film DUBBED (2020)',
    ]) {
      test('$raw is dubbed', () {
        expect(isDubbedTitle(raw), isTrue);
        expect(providerTitleTags(raw).first, dubbedBadge);
      });
    }
    for (final raw in [
      'TR-S: Taşacak Bu Deniz (2025)',
      'SUBS: The Lord of the Rings (2022) (US)',
      'Dubai Bling (2022)',
      'D: WWE Crown Jewel (2025)',
      'أفلام أطفال مدبلجة',
      'DUB: فيلم مدبلج',
      'BAKI-DOU: The Invincible Samurai',
    ]) {
      test('$raw is not marked dubbed', () {
        expect(isDubbedTitle(raw), isFalse);
        expect(providerTitleTags(raw), isNot(contains(dubbedBadge)));
      });
    }
  });

  test('live: 4K / 8K go, HD / SD / RAW stay (client 12 Nov)', () {
    String live(String raw) => cleanDisplayName(raw, keepQuality: true);
    expect(live('beIN ⁴ᴷ ³⁸⁴⁰ᵖ (EVENT ONLY)'), 'beIN (EVENT ONLY)');
    expect(live('BEIN SPORTS ⁸ᴷ ᴿᴬᵂ'), 'BEIN SPORTS RAW');
    expect(live('beIN SPORTS 1 4K'), 'beIN SPORTS 1');
    expect(live('NETFLIX MOVIES ᵁᴴᴰ ³⁸⁴⁰ᴾ'), 'NETFLIX MOVIES UHD');
    expect(live('MBC 1 ᴴᴰ'), 'MBC 1 HD');
    expect(live('MBC 1 SD'), 'MBC 1 SD');
    expect(live('MBC 1 ᴿᴬᵂ'), 'MBC 1 RAW');
    expect(isProviderAdOrHeaderChannel('TDM Promotional'), isTrue);
    // Found by the LG / Dart comparison on the whole catalog (12 Nov).
    expect(live('FRANCE 24 AR LQ'), 'FRANCE 24 LQ');
    expect(live('SYRIA 2 ᴿᴬᵂ ⁽ᴮᴷ⁾'), 'SYRIA 2 RAW (BK)');
  });

  test('hashtag titles keep their "#", banners do not', () {
    expect(cleanDisplayName('AS: #Alive (2020)'), '#Alive (2020)');
    expect(cleanDisplayName('#Alive (2020)'), '#Alive (2020)');
    expect(cleanDisplayName('### MBC 1 ###'), 'MBC 1');
  });
}
