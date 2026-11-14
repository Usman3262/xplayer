import 'dart:async';

import 'package:data/src/device/device_capabilities.dart';
import 'package:data/src/playback/lease_manager.dart';
import 'package:data/src/remote/api_exception.dart';
import 'package:data/src/remote/app_media_repository.dart';
import 'package:data/src/remote/media_models.dart';
import 'package:data/src/remote/player_lifecycle_gate.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

PlaybackSessionDto _dto(String id) => PlaybackSessionDto(
  playbackId: id,
  contentType: 'vod',
  streamId: '1',
  playUrl: 'http://example.invalid/x.mkv',
  leaseTtlSec: 60,
);

class _FakeMedia implements AppMediaRepository {
  int heartbeats = 0;
  final List<Map<String, Object?>?> heartbeatStats = [];
  final List<bool?> heartbeatPaused = [];
  int starts = 0;
  int stops = 0;
  Object? heartbeatError;
  Object? startError;
  Completer<void>? startGate;

  @override
  Future<PlaybackSessionDto> startPlayback({
    required String deviceId,
    required String contentType,
    required String streamId,
    String? profileId,
    String? containerExtension,
    int? maxHeight,
    String? tier,
    List<String>? codecs,
    bool force = false,
    String? title,
    String? categoryName,
  }) async {
    starts++;
    final gate = startGate;
    if (gate != null) await gate.future;
    if (starts > 1 && startError != null) throw startError!;
    return _dto('p$starts');
  }

  @override
  Future<PlaybackSessionDto> heartbeatPlayback({
    required String playbackId,
    required String deviceId,
    Map<String, Object?>? stats,
    bool? paused,
  }) async {
    heartbeats++;
    heartbeatStats.add(stats);
    heartbeatPaused.add(paused);
    if (heartbeatError != null) throw heartbeatError!;
    return _dto(playbackId);
  }

  @override
  Future<PlaybackSessionDto> stopPlayback({
    required String playbackId,
    required String deviceId,
  }) async {
    stops++;
    return _dto(playbackId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('failed renew after heartbeat 404 stops heartbeating the dead lease', () {
    fakeAsync((async) {
      final media = _FakeMedia();
      var lost = 0;
      final lease = LeaseManager(
        media: media,
        deviceId: 'd',
        onLeaseLost: () => lost++,
      );
      unawaited(lease.start(contentType: 'vod', streamId: '1'));
      async.flushMicrotasks();
      expect(media.heartbeats, 1, reason: 'first beat is immediate');

      media.heartbeatError = ApiException('gone', statusCode: 404);
      media.startError = ApiException('upstream', statusCode: 502);
      async.elapse(const Duration(seconds: 25));
      expect(lost, 1);
      final beatsAfterLoss = media.heartbeats;

      async.elapse(const Duration(minutes: 5));
      expect(media.heartbeats, beatsAfterLoss,
          reason: 'no periodic heartbeat/renew loop after the lease was lost');
      expect(lost, 1);
      expect(media.starts, 2, reason: 'exactly one renew attempt');
      lease.dispose();
    });
  });

  test('lease that arrives after the player gave up is released, not kept', () {
    fakeAsync((async) {
      final media = _FakeMedia()..startGate = Completer<void>();
      final lease = LeaseManager(media: media, deviceId: 'd');
      Object? error;
      unawaited(
        lease.start(contentType: 'vod', streamId: '1').then(
              (_) {},
              onError: (Object e) => error = e,
            ),
      );
      async.flushMicrotasks();
      // Player timed out and stopped the lease manager.
      unawaited(lease.stop());
      lease.dispose();
      async.flushMicrotasks();
      // Backend reply arrives late.
      media.startGate!.complete();
      async.flushMicrotasks();
      expect(error, isA<StateError>());
      expect(media.stops, 1);
      async.elapse(const Duration(minutes: 3));
      expect(media.heartbeats, 0);
    });
  });

  test('heartbeat carries player stats; none without a provider', () {
    fakeAsync((async) {
      final media = _FakeMedia();
      final lease = LeaseManager(media: media, deviceId: 'd');
      unawaited(lease.start(contentType: 'vod', streamId: '1'));
      async.flushMicrotasks();
      expect(media.heartbeatStats.single, isNull);
      lease.statsProvider = () async => {'engine': 'mpv', 'droppedFrames': 2};
      async.elapse(const Duration(seconds: 25));
      expect(media.heartbeatStats.last, {'engine': 'mpv', 'droppedFrames': 2});
      lease.dispose();
    });
  });

  test('a failing or slow stats provider never blocks the heartbeat', () {
    fakeAsync((async) {
      final media = _FakeMedia();
      final lease = LeaseManager(media: media, deviceId: 'd')
        ..statsProvider = () async => throw StateError('mpv busy');
      unawaited(lease.start(contentType: 'vod', streamId: '1'));
      async.flushMicrotasks();
      expect(media.heartbeats, 1);
      expect(media.heartbeatStats.single, isNull);
      lease.statsProvider = () => Completer<Map<String, Object?>?>().future;
      async.elapse(const Duration(seconds: 25));
      expect(media.heartbeats, 2, reason: 'sent after the 1 s stats limit');
      expect(media.heartbeatStats.last, isNull);
      lease.dispose();
    });
  });

  test('successful renew keeps heartbeating the new lease', () {
    fakeAsync((async) {
      final media = _FakeMedia();
      final lease = LeaseManager(media: media, deviceId: 'd');
      unawaited(lease.start(contentType: 'vod', streamId: '1'));
      async.flushMicrotasks();
      media.heartbeatError = ApiException('gone', statusCode: 404);
      async.elapse(const Duration(seconds: 25));
      expect(lease.playbackId, 'p2');
      media.heartbeatError = null;
      final before = media.heartbeats;
      async.elapse(const Duration(minutes: 2));
      expect(media.heartbeats, greaterThan(before));
      lease.dispose();
    });
  });

  test('lease DTO parses backend-approved alternate play URLs', () {
    final dto = PlaybackSessionDto.fromJson({
      'playbackId': 'p',
      'contentType': 'vod',
      'streamId': '1',
      'playUrl': 'http://h/movie/u/p/1.mkv',
      'alternatePlayUrls': ['https://h/movie/u/p/1.mkv', '', 3],
    });
    expect(dto.alternatePlayUrls, ['https://h/movie/u/p/1.mkv']);
    expect(
      PlaybackSessionDto.fromJson({
        'playbackId': 'p', 'contentType': 'vod', 'streamId': '1', 'playUrl': 'x',
        'providerAuthUrl': 'http://h/player_api.php?username=u&password=p',
      }).providerAuthUrl,
      'http://h/player_api.php?username=u&password=p',
    );
    final old = PlaybackSessionDto.fromJson({
      'playbackId': 'p', 'contentType': 'vod', 'streamId': '1', 'playUrl': 'x',
    });
    expect(old.alternatePlayUrls, isEmpty);
  });

  group('PlayerLifecycleGate', () {
    test('a tracked teardown delays the next open and settle', () async {
      final teardown = Completer<void>();
      PlayerLifecycleGate.track(teardown.future);
      final order = <String>[];
      final open = PlayerLifecycleGate.enqueue(() async => order.add('open'));
      expect(
        await PlayerLifecycleGate.settle(const Duration(milliseconds: 30)),
        isFalse,
      );
      expect(order, isEmpty);
      order.add('teardown');
      teardown.complete();
      await open;
      expect(order, ['teardown', 'open']);
      expect(await PlayerLifecycleGate.settle(const Duration(seconds: 1)), isTrue);
    });

    test('a failing teardown does not block later work', () async {
      PlayerLifecycleGate.track(Future<void>.error(StateError('x')));
      expect(await PlayerLifecycleGate.enqueue(() async => 1), 1);
    });
  });

  group('CodecMaxRes', () {
    test('UHD support uses the rate measured at 3840x2160', () {
      // Independent upper bounds: the 4096x4096 corner is only reachable at a
      // low rate, while 3840x2160@30 is supported.
      const hevc = CodecMaxRes(
        mime: 'video/hevc', width: 4096, height: 4096, fps: 12,
        uhdFps: 30, fhdFps: 120,
      );
      expect(hevc.supports(w: 3840, h: 2160), isTrue);
      expect(hevc.supports(w: 1920, h: 1080, fps: 60), isTrue);
      expect(
        DeviceCapabilities.computeTier(
          totalRamMb: 8192, isLowRamDevice: false, hevc: hevc),
        DeviceTier.high,
      );
    });

    test('unsupported UHD size is rejected even with large bounds', () {
      const hevc = CodecMaxRes(
        mime: 'video/hevc', width: 4096, height: 2304, fps: 30, uhdFps: 0,
      );
      expect(hevc.supports(w: 3840, h: 2160), isFalse);
    });

    test('capabilities cached by older builds keep the previous rule', () {
      final legacy = CodecMaxRes.fromJson(
        {'mime': 'video/hevc', 'width': 4096, 'height': 2304, 'fps': 30},
      );
      expect(legacy.uhdFps, isNull);
      expect(legacy.supports(w: 3840, h: 2160), isTrue);
      final round = CodecMaxRes.fromJson(
        const CodecMaxRes(
          mime: 'video/hevc', width: 1, height: 1, fps: 1, uhdFps: 30,
        ).toJson(),
      );
      expect(round.uhdFps, 30);
    });
  });

  group('pause rule (Usman 13 Nov: heartbeats while paused up to 30 min)', () {
    LeaseManager started(_FakeMedia media, FakeAsync async) {
      final lease = LeaseManager(media: media, deviceId: 'd1');
      lease.start(contentType: 'vod', streamId: 's1');
      async.flushMicrotasks();
      return lease;
    }

    test('paused: heartbeats go on with paused=true; play sends paused=false', () {
      fakeAsync((async) {
        final media = _FakeMedia();
        final lease = started(media, async);
        async.elapse(const Duration(seconds: 1));
        final before = media.heartbeats;
        lease.onPausedChanged(true);
        lease.onPausedChanged(true); // repeated calls change nothing
        async.flushMicrotasks();
        expect(media.heartbeats, before + 1); // sent at once
        expect(media.heartbeatPaused.last, isTrue);
        async.elapse(const Duration(minutes: 10));
        expect(media.heartbeats, greaterThan(before + 5)); // still beating
        expect(media.heartbeatPaused.last, isTrue);
        expect(media.stops, 0);
        lease.onPausedChanged(false);
        async.flushMicrotasks();
        expect(media.heartbeatPaused.last, isFalse);
        expect(lease.isActive, isTrue);
        lease.dispose();
      });
    });

    test('30 min paused: lease released; Play starts a new lease', () {
      fakeAsync((async) {
        final media = _FakeMedia();
        final lease = started(media, async);
        lease.onPausedChanged(true);
        async.elapse(const Duration(minutes: 29, seconds: 50));
        expect(media.stops, 0);
        expect(lease.isActive, isTrue);
        async.elapse(const Duration(seconds: 20));
        expect(media.stops, 1);
        expect(lease.isActive, isFalse);
        final beats = media.heartbeats;
        async.elapse(const Duration(minutes: 5));
        expect(media.heartbeats, beats); // no beats on a released lease
        lease.onPausedChanged(false);
        async.flushMicrotasks();
        expect(media.starts, 2);
        expect(lease.isActive, isTrue);
        lease.dispose();
      });
    });

    test('a short pause never releases the lease', () {
      fakeAsync((async) {
        final media = _FakeMedia();
        final lease = started(media, async);
        lease.onPausedChanged(true);
        async.elapse(const Duration(minutes: 20));
        lease.onPausedChanged(false);
        async.elapse(const Duration(minutes: 20));
        expect(media.stops, 0);
        expect(media.starts, 1);
        lease.dispose();
      });
    });
  });
}
