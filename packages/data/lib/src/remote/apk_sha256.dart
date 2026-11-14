import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// Hex sha256 of [bytes]. Used to verify a downloaded APK against
/// `builds[].sha256` from `GET /v1/app/version`.
String sha256Hex(Uint8List bytes) => sha256.convert(bytes).toString();

/// Returns true when [expectedHex] is null/empty (nothing to check) or matches.
bool apkSha256Matches(Uint8List bytes, String? expectedHex) {
  final want = normalizeSha256Hex(expectedHex);
  if (want == null) return true;
  return sha256Hex(bytes) == want;
}

/// Parse a hex digest; null if malformed.
String? normalizeSha256Hex(String? raw) {
  final s = raw?.trim().toLowerCase();
  if (s == null || s.isEmpty) return null;
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(s)) return null;
  return s;
}

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

/// Download [url] to [dest], hashing as we go (streaming, no full-file RAM).
/// Throws if sha256 mismatches when [expectedSha256] is set.
Future<String> downloadApkVerified({
  required String url,
  required File dest,
  String? expectedSha256,
  void Function(int received, int? total)? onProgress,
  http.Client? client,
}) async {
  final owns = client == null;
  final c = client ?? http.Client();
  try {
    final req = http.Request('GET', Uri.parse(url));
    final res = await c.send(req).timeout(const Duration(minutes: 30));
    if (res.statusCode != 200) {
      throw StateError('APK download HTTP ${res.statusCode}');
    }
    final total = res.contentLength;
    final digestSink = _DigestSink();
    final hasher = sha256.startChunkedConversion(digestSink);
    await dest.parent.create(recursive: true);
    final out = dest.openWrite();
    var received = 0;
    try {
      await for (final chunk in res.stream) {
        hasher.add(chunk);
        out.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      hasher.close();
    } finally {
      await out.close();
    }
    final digest = digestSink.value?.toString();
    if (digest == null) {
      throw StateError('APK sha256 digest missing');
    }
    final want = normalizeSha256Hex(expectedSha256);
    if (want != null && digest != want) {
      try {
        await dest.delete();
      } catch (_) {}
      throw StateError('APK sha256 mismatch (got $digest)');
    }
    return digest;
  } finally {
    if (owns) c.close();
  }
}

/// Decode base64 body to bytes then verify (tests / small fixtures).
bool apkSha256MatchesBase64(String base64Body, String? expectedHex) {
  return apkSha256Matches(base64Decode(base64Body), expectedHex);
}
