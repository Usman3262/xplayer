import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;

/// One hop of a media request: which server answered and with what status.
class MediaHop {
  const MediaHop(this.host, this.port, this.status, {this.error});
  final String host;
  final int port;
  final int? status;
  final String? error;

  @override
  String toString() =>
      '$host:$port ${status ?? 'ERR'}${error == null ? '' : ' ($error)'}';
}

/// Follows the media URL's redirects by hand (Range bytes=0-0, same headers
/// as the player) and records every server and status on the way, so a
/// refusal such as HTTP 456 can be pinned to the gateway or the media server.
/// Only host, port and status are kept; never the path, query or credentials.
Future<List<MediaHop>> probeMediaRedirectChain(
  String url, {
  Map<String, String> headers = const {},
  int maxHops = 4,
  Duration timeout = const Duration(seconds: 8),
}) async {
  final hops = <MediaHop>[];
  // No raw sockets in a web app (LG webOS build): nothing to probe.
  if (kIsWeb) return hops;
  final client = HttpClient()..connectionTimeout = timeout;
  var uri = Uri.tryParse(url);
  try {
    for (var i = 0; i < maxHops && uri != null; i++) {
      final host = uri.host;
      final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
      try {
        final req = await client.getUrl(uri).timeout(timeout);
        req.followRedirects = false;
        headers.forEach(req.headers.set);
        req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
        final res = await req.close().timeout(timeout);
        // Read at most a little and drop the rest (body of a 206/4xx is tiny).
        unawaited(res.listen((_) {}).cancel());
        hops.add(MediaHop(host, port, res.statusCode));
        final location = res.headers.value(HttpHeaders.locationHeader);
        if (!res.isRedirect || location == null) break;
        uri = uri.resolve(location);
      } on Object catch (e) {
        hops.add(MediaHop(host, port, null, error: e.runtimeType.toString()));
        break;
      }
    }
  } finally {
    client.close(force: true);
  }
  return hops;
}
