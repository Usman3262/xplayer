/// YouTube link for a provider trailer value (Xtream `youtube_trailer`),
/// or null when there is no usable trailer (client 20 Oct #3: the Trailer
/// button played the movie; hide it when there is no real trailer).
///
/// Accepts a bare 11-character video id or a youtube.com / youtu.be URL.
Uri? youtubeTrailerUri(String? raw) {
  final v = raw?.trim() ?? '';
  if (v.isEmpty) return null;
  final id = RegExp(r'^[A-Za-z0-9_-]{11}$');
  if (id.hasMatch(v)) {
    return Uri.https('www.youtube.com', '/watch', {'v': v});
  }
  final uri = Uri.tryParse(v.startsWith('http') ? v : 'https://$v');
  if (uri == null) return null;
  final host = uri.host.toLowerCase();
  String? vid;
  if (host == 'youtu.be' && uri.pathSegments.isNotEmpty) {
    vid = uri.pathSegments.first;
  } else if (host == 'youtube.com' ||
      host.endsWith('.youtube.com')) {
    vid = uri.queryParameters['v'] ??
        (uri.pathSegments.length >= 2 &&
                (uri.pathSegments.first == 'embed' ||
                    uri.pathSegments.first == 'shorts')
            ? uri.pathSegments[1]
            : null);
  }
  if (vid == null || !id.hasMatch(vid)) return null;
  return Uri.https('www.youtube.com', '/watch', {'v': vid});
}
