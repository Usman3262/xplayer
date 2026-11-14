import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Result of the device-side provider login; never holds credentials.
class ProviderAuthResult {
  const ProviderAuthResult({
    this.httpStatus,
    this.auth,
    this.status,
    this.activeCons,
    this.maxCons,
    this.error,
  });
  final int? httpStatus;
  final int? auth;
  final String? status;
  final String? activeCons;
  final String? maxCons;
  final String? error;

  @override
  String toString() => error != null
      ? 'error=$error'
      : 'http=$httpStatus auth=${auth ?? '?'} status=${status ?? '?'} '
          'cons=${activeCons ?? '?'}/${maxCons ?? '?'}';
}

/// Logs into the provider from this device (player_api.php account info), as
/// standard Xtream players do before streaming. Some providers only accept a
/// stream from an IP that logged in recently.
Future<ProviderAuthResult> loginProviderFromDevice(
  String authUrl, {
  Map<String, String> headers = const {},
  Duration timeout = const Duration(seconds: 6),
}) async {
  final uri = Uri.tryParse(authUrl);
  if (uri == null) return const ProviderAuthResult(error: 'badUrl');
  // No raw sockets in a web app (LG webOS build); a browser cannot do this.
  if (kIsWeb) return const ProviderAuthResult(error: 'web');
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final req = await client.getUrl(uri).timeout(timeout);
    headers.forEach(req.headers.set);
    final res = await req.close().timeout(timeout);
    final body = await res
        .transform(utf8.decoder)
        .join()
        .timeout(timeout);
    Map<String, dynamic>? info;
    try {
      final j = jsonDecode(body);
      if (j is Map && j['user_info'] is Map) {
        info = Map<String, dynamic>.from(j['user_info'] as Map);
      }
    } catch (_) {}
    return ProviderAuthResult(
      httpStatus: res.statusCode,
      auth: info?['auth'] is int ? info!['auth'] as int : int.tryParse('${info?['auth']}'),
      status: info?['status']?.toString(),
      activeCons: info?['active_cons']?.toString(),
      maxCons: info?['max_connections']?.toString(),
    );
  } on Object catch (e) {
    return ProviderAuthResult(error: e.runtimeType.toString());
  } finally {
    client.close(force: true);
  }
}
