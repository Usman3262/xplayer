import 'package:data/data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player_tv/core/remote_config.dart';

RemoteConfig flags(Map<String, bool> f) => RemoteConfig.tryParse({'version': 1, 'flags': f})!;

void main() {
  test('switched-off features send their pages Home', () {
    final c = flags({'sports': false, 'movies': false, 'downloads': false, 'search': true});
    expect(featureOffRedirect('/sports', c), '/home');
    expect(featureOffRedirect('/match-centre/abc', c), '/home');
    expect(featureOffRedirect('/movies', c), '/home');
    expect(featureOffRedirect('/offline/42', c), '/home');
    expect(featureOffRedirect('/search', c), isNull);
    expect(featureOffRedirect('/series', c), isNull); // not in config → on
  });

  test('prefix match is exact (no /live vs /library mix-up)', () {
    final c = flags({'live_tv': false});
    expect(featureOffRedirect('/live', c), '/home');
    expect(featureOffRedirect('/live/channel/1', c), '/home');
    expect(featureOffRedirect('/library', c), isNull);
  });

  test('empty config (no backend) blocks nothing', () {
    expect(featureOffRedirect('/sports', RemoteConfig.empty), isNull);
  });
}
