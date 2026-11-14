import 'package:domain/domain.dart';
import 'package:test/test.dart';

// Client 31 Oct: live channel names keep the provider's quality label, so the
// 1080p and SD versions of a channel no longer read the same ("MBC 1" twice).
// Names as the provider sends them (production, 31 Oct).
void main() {
  // Client 12 Nov: 4K / 8K (and their pixel counts) leave live names.
  test('live names keep RAW / HD / FHD / UHD / HEVC / SD', () {
    String live(String raw) => cleanDisplayName(raw, keepQuality: true);
    expect(live('MBC 1 ᴿᴬᵂ'), 'MBC 1 RAW');
    expect(live('MBC 1 ᴴᴰ'), 'MBC 1 HD');
    expect(live('MBC 1'), 'MBC 1');
    expect(live('ALWAN SPORT 1 ᴿᴬᵂ'), 'ALWAN SPORT 1 RAW');
    expect(live('SOLO SPORT 1 ʰᵉᵛᶜ'), 'SOLO SPORT 1 HEVC');
    expect(live('beIN SPORTS 1 ᶠᴴᴰ'), 'beIN SPORTS 1 FHD');
    expect(live('beIN ⁴ᴷ ³⁸⁴⁰ᵖ (EVENT ONLY)'), 'beIN (EVENT ONLY)');
    expect(live('beIN SPORTS 1 SD'), 'beIN SPORTS 1 SD');
  });

  test('live names still drop the decoration around the label', () {
    String live(String raw) => cleanDisplayName(raw, keepQuality: true);
    expect(live('BEIN SPORTS ⁸ᴷ ᴿᴬᵂ'), 'BEIN SPORTS RAW');
    expect(live('ALWAN SPORT ⚽ RAW'), 'ALWAN SPORT RAW');
    expect(live('MBC 1 RAW ▼'), 'MBC 1 RAW');
    expect(live('#### MBC 1 RAW ####'), 'MBC 1 RAW');
    expect(live('SOLO SPORT ᴮᴱ'), 'SOLO SPORT');
    expect(live('AR: MBC 1 HD'), 'MBC 1 HD');
  });

  test('1080p and SD versions get different names', () {
    final names = ['MBC 1 ᴿᴬᵂ', 'MBC 1 ᴴᴰ', 'MBC 1']
        .map((n) => cleanDisplayName(n, keepQuality: true))
        .toSet();
    expect(names, hasLength(3));
  });

  test('live MediaItem and LiveChannel keep the label; movies do not change', () {
    const ch = MediaItem(id: '1', title: 'MBC 1 RAW', kind: MediaKind.live);
    expect(ch.displayTitle, 'MBC 1 RAW');
    const live = LiveChannel(
      id: '1',
      name: 'MBC 1 ᴿᴬᵂ',
      code: 'LIVE',
      nowTitle: '',
      nextTitle: '',
    );
    expect(live.displayName, 'MBC 1 RAW');
    // Categories and movies keep the 16 Oct rule.
    expect(cleanDisplayName('ALWAN SPORT ᴿᴬᵂ'), 'ALWAN SPORT');
    const movie = MediaItem(id: '2', title: 'Rawhide (1959)', kind: MediaKind.movie);
    expect(movie.displayTitle, 'Rawhide (1959)');
  });
}
