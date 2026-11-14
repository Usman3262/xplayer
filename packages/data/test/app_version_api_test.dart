import 'dart:typed_data';

import 'package:data/data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('compareAppVersions: semver then optional +build', () {
    expect(compareAppVersions('6.0.22', '6.0.23'), lessThan(0));
    expect(compareAppVersions('6.0.23', '6.0.22'), greaterThan(0));
    expect(compareAppVersions('6.0.23', '6.0.23'), 0);
    expect(compareAppVersions('6.0.23+100', '6.0.23+105'), lessThan(0));
    expect(compareAppVersions('6.0.23+105', '6.0.23'), 0);
    expect(isAppVersionNewer('6.0.23', '6.0.22'), isTrue);
  });

  test('no signed-config keys, mirrors or release links are built in', () {
    expect(kConfigPublicKeys, isEmpty);
    expect(kConfigMirrorUrls, isEmpty);
    expect(AppReleaseUrls.tvApk, isEmpty);
    expect(AppReleaseUrls.mobileApk, isEmpty);
  });

  test('resolveAppUpdateGate forces when below minVersion.tv', () {
    final remote = AppVersionDto.fromJson({
      'minVersion': {'mobile': null, 'tv': '6.0.22'},
      'builds': [
        {
          'id': 'android-tv',
          'platform': 'Android TV',
          'version': '6.0.23',
          'latestUrl': 'https://dl.example/tv.apk',
          'sha256': 'e9f688585ed78fcf1806783f0d80b6dd4aa06f3863fb38bf98fe1afc53f1154a',
        },
      ],
    });
    final gate = resolveAppUpdateGate(
      installedVersion: '6.0.18',
      installedBuild: 104,
      isTv: true,
      remote: remote,
    );
    expect(gate.required, isTrue);
    expect(gate.offerUpdate, isTrue);
    expect(gate.updateUrl, 'https://dl.example/tv.apk');
    expect(gate.sha256, startsWith('e9f688'));
  });

  test('apkSha256Matches', () {
    final bytes = Uint8List.fromList([1, 2, 3]);
    final hex = sha256Hex(bytes);
    expect(apkSha256Matches(bytes, hex), isTrue);
    expect(apkSha256Matches(bytes, '00' * 32), isFalse);
    expect(apkSha256Matches(bytes, null), isTrue);
  });

  // Client 23 Oct: "new version released → in-app notification" (optional).
  AppVersionDto remote({String? ios}) => AppVersionDto.fromJson({
        'minVersion': {'mobile': null, 'tv': null},
        'builds': [
          {'id': 'android-mobile', 'platform': 'Android Mobile', 'version': '6.0.24+110',
            'latestUrl': 'https://download.example/mobile.apk'},
          if (ios != null)
            {'id': 'ios', 'platform': 'iOS', 'version': ios,
              'latestUrl': 'https://apps.apple.com/app/id000'},
        ],
      });

  test('newer Android build: offered, not forced, APK link', () {
    final g = resolveAppUpdateGate(installedVersion: '6.0.23', installedBuild: 109, isTv: false, remote: remote());
    expect(g.offerUpdate, isTrue);
    expect(g.required, isFalse);
    expect(g.updateUrl, 'https://download.example/mobile.apk');
  });

  test('same version: nothing offered', () {
    final g = resolveAppUpdateGate(installedVersion: '6.0.24', installedBuild: 110, isTv: false, remote: remote());
    expect(g.offerUpdate, isFalse);
  });

  test('iPhone never gets the Android APK', () {
    final g = resolveAppUpdateGate(installedVersion: '6.0.23', installedBuild: 109, isTv: false, isIos: true, remote: remote());
    expect(g.offerUpdate, isFalse);
    expect(g.updateUrl, isNull);
  });

  test('iPhone with its own entry: offered with the store link', () {
    final g = resolveAppUpdateGate(installedVersion: '6.0.23', installedBuild: 109, isTv: false, isIos: true, remote: remote(ios: '6.0.24+110'));
    expect(g.offerUpdate, isTrue);
    expect(g.updateUrl, 'https://apps.apple.com/app/id000');
  });

  test('in-app installer gets a direct APK, never the Play page', () {
    final remote = AppVersionDto.fromJson({
      'builds': [
        {
          'id': 'android-mobile',
          'platform': 'Android Mobile',
          'version': '6.0.24+113',
          'downloadUrl': 'https://dl.example/android/mobile/m-113.apk',
          'latestUrl': 'https://play.google.com/store/apps/details?id=com.example.app',
          'sha256': 'a' * 64,
        },
      ],
    });
    final g = resolveAppUpdateGate(installedVersion: '6.0.23', installedBuild: 110, isTv: false, remote: remote);
    expect(g.offerUpdate, isTrue);
    expect(g.apkUrl, 'https://dl.example/android/mobile/m-113.apk');
    expect(g.sha256, 'a' * 64);
  });

  test('releases.json relative paths are ignored without a download host', () {
    final remote = AppVersionDto.fromJson({
      'builds': [
        {'id': 'android-tv', 'platform': 'Android TV', 'version': '6.0.24+114', 'file': 'android/tv/t-114.apk', 'latestUrl': 'tv.apk'},
      ],
    });
    final b = remote.buildFor(tv: true)!;
    expect(AppReleaseUrls.installPage, isEmpty);
    expect(b.downloadUrl, isNull);
    expect(b.latestUrl, isNull);
  });

  test('backend still on 6.0.19: no prompt for 6.0.23 installs (publish needed)', () {
    final remote = AppVersionDto.fromJson({
      'builds': [
        {'id': 'android-tv', 'platform': 'Android TV', 'version': '6.0.19', 'latestUrl': 'https://dl.example/tv.apk'},
      ],
    });
    final g = resolveAppUpdateGate(installedVersion: '6.0.23', installedBuild: 112, isTv: true, remote: remote);
    expect(g.offerUpdate, isFalse);
  });
}
