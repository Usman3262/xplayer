import 'dart:ffi';

import 'package:data/data.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stand-in for media_kit's generated libmpv bindings: records what the app
/// passes to mpv_set_property_async (format 1 = MPV_FORMAT_STRING, char**).
class _FakeMpv {
  final calls = <(String, int, String, int)>[];
  int result = 0;
  // ignore: non_constant_identifier_names (same name as the libmpv binding)
  int mpv_set_property_async(
    Pointer ctx,
    int replyUserdata,
    Pointer<Char> name,
    int format,
    Pointer<Void> data,
  ) {
    calls.add((
      name.cast<Utf8>().toDartString(),
      format,
      data.cast<Pointer<Utf8>>().value.toDartString(),
      replyUserdata,
    ));
    return result;
  }
}

class _FakeNative {
  _FakeNative(this.mpv, {int ctx = 0x1000}) : ctx = Pointer<Void>.fromAddress(ctx);
  final _FakeMpv mpv;
  final Pointer<Void> ctx;
  bool disposed = false;
}

void main() {
  test('writes go to mpv_set_property_async as a string (char**), in order', () {
    final mpv = _FakeMpv();
    final native = _FakeNative(mpv);
    expect(appMpvSetAsyncForTest(native, 'vid', 'no'), isTrue);
    expect(appMpvSetAsyncForTest(native, 'hwdec', 'mediacodec-copy'), isTrue);
    expect(mpv.calls.map((c) => (c.$1, c.$2, c.$3)), [
      ('vid', 1, 'no'),
      ('hwdec', 1, 'mediacodec-copy'),
    ]);
    // Reply ids never collide with media_kit's own counter (starts at 0).
    expect(mpv.calls.every((c) => c.$4 >= 1 << 52), isTrue);
    expect(mpv.calls[1].$4, mpv.calls[0].$4 + 1);
  });

  test('mpv refuses the request: the caller falls back to the blocking write', () {
    final mpv = _FakeMpv()..result = -1;
    expect(appMpvSetAsyncForTest(_FakeNative(mpv), 'vid', 'no'), isFalse);
  });

  test('no libmpv handle yet: fall back; disposed player: nothing to do', () {
    final mpv = _FakeMpv();
    expect(appMpvSetAsyncForTest(_FakeNative(mpv, ctx: 0), 'vid', 'no'), isFalse);
    final gone = _FakeNative(mpv)..disposed = true;
    expect(appMpvSetAsyncForTest(gone, 'vid', 'no'), isTrue);
    expect(mpv.calls, isEmpty);
  });

  test('a player without libmpv (other object): fall back', () {
    expect(appMpvSetAsyncForTest(Object(), 'vid', 'no'), isFalse);
  });
}
