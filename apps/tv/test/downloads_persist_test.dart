import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_tv/core/tv_downloads.dart';

void main() {
  test('persisted download entry has no source URL and restores fields', () {
    const d = TvDownload(
      id: '123',
      title: 'Movie',
      contentType: 'vod',
      status: TvDownloadStatus.downloading,
      container: 'mkv',
      grantId: 'g1',
      fileName: '123.mkv',
      received: 50,
      total: 100,
    );
    final raw = jsonEncode(d.toJson());
    expect(raw.contains('http'), isFalse);
    expect(raw.contains('downloadUrl'), isFalse);
    final back = TvDownload.fromJson(
      Map<String, dynamic>.from(jsonDecode(raw) as Map),
    );
    expect(back.grantId, 'g1');
    expect(back.received, 50);
    expect(back.fraction, 0.5);
    expect(back.status, TvDownloadStatus.downloading);
  });

  test('unknown stored status falls back to paused', () {
    final back = TvDownload.fromJson({'id': '1', 'status': 'bogus'});
    expect(back.status, TvDownloadStatus.paused);
  });
}
