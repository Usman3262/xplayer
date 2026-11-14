import 'dart:io';

import 'api_config.dart';

/// Client 18 Oct #16: opening a video with no internet hung for up to a
/// minute (30 s request timeouts, one after another). A TCP connect to the
/// API host answers in a few seconds either way.
Future<bool> appServerReachable({
  Duration timeout = const Duration(seconds: 4),
}) async {
  final uri = Uri.tryParse(ApiConfig.fromEnvironment().baseUrl);
  final host = uri?.host;
  if (host == null || host.isEmpty) return true;
  final port = uri!.hasPort ? uri.port : (uri.scheme == 'http' ? 80 : 443);
  try {
    final s = await Socket.connect(host, port, timeout: timeout);
    s.destroy();
    return true;
  } catch (_) {
    return false;
  }
}

/// Client 5 Nov: do not say "No internet" when the customer's connection
/// works and only the the app server (or the provider behind it) fails.
/// A TCP connect to public DNS hosts answers in about a second either way.
Future<bool> deviceHasInternet({
  Duration timeout = const Duration(seconds: 3),
}) async {
  for (final (host, port) in const [('1.1.1.1', 443), ('8.8.8.8', 53)]) {
    try {
      final s = await Socket.connect(host, port, timeout: timeout);
      s.destroy();
      return true;
    } catch (_) {}
  }
  return false;
}
