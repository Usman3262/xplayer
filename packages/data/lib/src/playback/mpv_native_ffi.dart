import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// Reply ids far above media_kit's own async request counter (it starts at
/// 0), so a reply can never complete one of media_kit's requests.
int _appAsyncReplyId = 1 << 52;

/// Queues [key] = [value] on mpv without waiting; false when the native
/// player does not expose libmpv (then the caller writes the blocking way).
bool appMpvSetAsyncNative(Object native, String key, String value) {
  Pointer<Utf8>? name;
  Pointer<Utf8>? text;
  Pointer<Pointer<Utf8>>? data;
  try {
    final dyn = native as dynamic;
    if (dyn.disposed == true) return true; // nothing to set any more
    final Pointer ctx = dyn.ctx as Pointer;
    if (ctx.address == 0) return false;
    final mpv = dyn.mpv;
    name = key.toNativeUtf8();
    text = value.toNativeUtf8();
    data = calloc<Pointer<Utf8>>()..value = text;
    // MPV_FORMAT_STRING = 1; mpv copies the name and the value before it
    // returns, so they are freed right after.
    final rc = mpv.mpv_set_property_async(
      ctx,
      _appAsyncReplyId++,
      name.cast<Char>(),
      1,
      data.cast<Void>(),
    ) as int;
    return rc >= 0;
  } catch (_) {
    return false;
  } finally {
    if (data != null) calloc.free(data);
    if (text != null) calloc.free(text);
    if (name != null) calloc.free(name);
  }
}
