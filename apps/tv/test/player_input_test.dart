import 'package:player_tv/core/tv_live_zap.dart';
import 'package:player_tv/features/player/tv_player_input.dart';
import 'package:domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

TvBackAction _back({
  bool pendingZap = false,
  bool listOpen = false,
  bool live = true,
  bool hasChannelList = true,
  bool failed = false,
  bool ready = true,
  bool exitArmed = false,
}) =>
    tvBackAction(
      pendingZap: pendingZap,
      listOpen: listOpen,
      live: live,
      hasChannelList: hasChannelList,
      failed: failed,
      ready: ready,
      exitArmed: exitArmed,
    );

void main() {
  group('Back sequence (client #5 #16)', () {
    test('live: Back -> list, Back -> close list, Back again -> exit', () {
      expect(_back(), TvBackAction.openChannelList);
      expect(_back(listOpen: true), TvBackAction.closeChannelList);
      expect(_back(exitArmed: true), TvBackAction.confirmExit);
    });

    test('live: list opens in every playback state', () {
      for (final s in [
        (failed: false, ready: false), // loading / buffering
        (failed: false, ready: true), // playing / paused
        (failed: true, ready: false), // error
      ]) {
        expect(
          _back(failed: s.failed, ready: s.ready),
          TvBackAction.openChannelList,
          reason: '$s',
        );
      }
    });

    test('a channel being chosen is cancelled first', () {
      expect(_back(pendingZap: true, listOpen: true),
          TvBackAction.cancelPendingZap);
    });

    test('movie/series: playing or paused asks before leaving', () {
      expect(_back(live: false, hasChannelList: false),
          TvBackAction.confirmExit);
    });

    test('movie still loading or failed leaves directly', () {
      expect(_back(live: false, hasChannelList: false, ready: false),
          TvBackAction.leave);
      expect(_back(live: false, hasChannelList: false, failed: true),
          TvBackAction.leave);
    });
  });

  group('Live Up/Down (client #14 #18)', () {
    test('first press reveals the bar, next presses change channel', () {
      expect(
        tvLiveKeyAction(listOpen: false, barVisible: false, pendingZap: false),
        TvLiveKeyAction.revealBar,
      );
      expect(
        tvLiveKeyAction(listOpen: false, barVisible: true, pendingZap: false),
        TvLiveKeyAction.changeChannel,
      );
      expect(
        tvLiveKeyAction(listOpen: false, barVisible: false, pendingZap: true),
        TvLiveKeyAction.changeChannel,
      );
    });

    test('with the list open, keys belong to the list', () {
      expect(
        tvLiveKeyAction(listOpen: true, barVisible: true, pendingZap: false),
        TvLiveKeyAction.focusList,
      );
    });

    test('Up = next channel, Down = previous; wraps at the ends', () {
      expect(tvChannelDelta(upKey: true), 1);
      expect(tvChannelDelta(upKey: false), -1);
      final zap = LiveZapList([
        for (var i = 1; i <= 3; i++)
          MediaItem(id: 'c$i', title: 'Ch $i', kind: MediaKind.live),
      ]);
      expect(zap.step('c1', tvChannelDelta(upKey: true))!.id, 'c2');
      expect(zap.step('c2', tvChannelDelta(upKey: false))!.id, 'c1');
      expect(zap.step('c3', tvChannelDelta(upKey: true))!.id, 'c1');
      expect(zap.step('c1', tvChannelDelta(upKey: false))!.id, 'c3');
    });
  });
}
