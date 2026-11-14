import 'dart:async';
import 'dart:io';

/// Why a transfer stopped.
enum DownloadStop { completed, cancelled }

class DownloadCancelToken {
  bool _cancelled = false;
  final _listeners = <void Function()>[];

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final l in List.of(_listeners)) {
      l();
    }
  }

  void _onCancel(void Function() l) => _listeners.add(l);
}

/// Thrown for HTTP status / transport failures (message has no URL).
class DownloadTransferException implements Exception {
  DownloadTransferException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  /// 401/403/404/410: the grant or source is gone — re-authorize, do not
  /// just retry the same URL.
  bool get needsReauthorize =>
      statusCode == 401 ||
      statusCode == 403 ||
      statusCode == 404 ||
      statusCode == 410;

  /// 456 / 458 / 460: the provider line is busy (its one connection is in
  /// use on another device or player). Wait and try again.
  bool get lineBusy =>
      statusCode == 456 || statusCode == 458 || statusCode == 460;

  @override
  String toString() => message;
}

/// Streams [url] into [target] with HTTP Range resume.
///
/// - An existing partial file is continued with `Range: bytes=N-`. A `206`
///   appends; a `200` (server ignored Range) restarts from 0 — reported via
///   [onRestart] so the UI can say so. A `416` with a partial file the same
///   size as the source counts as complete.
/// - [onProgress] is called at most every [progressEvery].
/// - Cancel closes the socket at once (frees the provider connection).
/// - The URL is never put into exception messages or logs.
class DownloadEngine {
  DownloadEngine({HttpClient Function()? clientFactory})
      : _clientFactory = clientFactory ?? HttpClient.new;

  final HttpClient Function() _clientFactory;

  Future<DownloadStop> run({
    required Uri url,
    required File target,
    required DownloadCancelToken cancel,
    Map<String, String> headers = const {},
    void Function(int received, int? total)? onProgress,
    void Function()? onRestart,
    Duration progressEvery = const Duration(milliseconds: 500),
  }) async {
    if (cancel.isCancelled) return DownloadStop.cancelled;
    final client = _clientFactory()
      ..connectionTimeout = const Duration(seconds: 20)
      ..idleTimeout = const Duration(seconds: 20);
    cancel._onCancel(() => client.close(force: true));
    IOSink? sink;
    try {
      await target.parent.create(recursive: true);
      var have = await target.exists() ? await target.length() : 0;
      final req = await client.getUrl(url);
      headers.forEach(req.headers.set);
      if (have > 0) req.headers.set(HttpHeaders.rangeHeader, 'bytes=$have-');
      final res = await req.close();
      if (cancel.isCancelled) return DownloadStop.cancelled;

      if (res.statusCode == 416 && have > 0) {
        await res.drain<void>();
        return DownloadStop.completed;
      }
      if (res.statusCode != 200 && res.statusCode != 206) {
        await res.drain<void>().catchError((_) {});
        throw DownloadTransferException(
          'Source answered HTTP ${res.statusCode}',
          statusCode: res.statusCode,
        );
      }
      int? total;
      if (res.statusCode == 206) {
        final range = res.headers.value(HttpHeaders.contentRangeHeader);
        final m = RegExp(r'/(\d+)$').firstMatch(range ?? '');
        total = m != null
            ? int.parse(m.group(1)!)
            : (res.contentLength >= 0 ? have + res.contentLength : null);
        sink = target.openWrite(mode: FileMode.append);
      } else {
        if (have > 0) onRestart?.call();
        have = 0;
        total = res.contentLength >= 0 ? res.contentLength : null;
        sink = target.openWrite(mode: FileMode.write);
      }
      var received = have;
      var lastReport = DateTime.fromMillisecondsSinceEpoch(0);
      onProgress?.call(received, total);
      await for (final chunk in res) {
        if (cancel.isCancelled) break;
        sink.add(chunk);
        received += chunk.length;
        final now = DateTime.now();
        if (now.difference(lastReport) >= progressEvery) {
          lastReport = now;
          onProgress?.call(received, total);
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (cancel.isCancelled) return DownloadStop.cancelled;
      onProgress?.call(received, total ?? received);
      if (total != null && received < total) {
        throw DownloadTransferException(
          'Connection ended early ($received of $total bytes)',
        );
      }
      return DownloadStop.completed;
    } on DownloadTransferException {
      rethrow;
    } on FileSystemException catch (e) {
      // Includes "No space left on device".
      throw DownloadTransferException('Storage error: ${e.osError?.message ?? e.message}');
    } catch (e) {
      if (cancel.isCancelled) return DownloadStop.cancelled;
      throw DownloadTransferException('Network error (${e.runtimeType})');
    } finally {
      try {
        await sink?.close();
      } catch (_) {}
      client.close(force: true);
    }
  }
}
