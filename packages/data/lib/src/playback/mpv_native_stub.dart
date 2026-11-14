/// Web/no-FFI build: there is no libmpv handle, so callers use the blocking
/// media_kit write instead.
bool appMpvSetAsyncNative(Object native, String key, String value) => false;
