import 'package:media_kit/media_kit.dart';

/// Snapshot of selectable media_kit tracks (filters out sentinel auto/no).
class AppTrackSnapshot {
  const AppTrackSnapshot({
    required this.audios,
    required this.subtitles,
    required this.videos,
    required this.audio,
    required this.subtitle,
    required this.video,
  });

  final List<AudioTrack> audios;
  final List<SubtitleTrack> subtitles;
  final List<VideoTrack> videos;
  final AudioTrack audio;
  final SubtitleTrack subtitle;
  final VideoTrack video;
}

bool appIsSelectableTrackId(String id) => id != 'auto' && id != 'no';

List<AudioTrack> appSelectableAudio(Tracks tracks) =>
    tracks.audio.where((t) => appIsSelectableTrackId(t.id)).toList();

List<SubtitleTrack> appSelectableSubtitles(Tracks tracks) =>
    tracks.subtitle.where((t) => appIsSelectableTrackId(t.id)).toList();

List<VideoTrack> appSelectableVideo(Tracks tracks) =>
    tracks.video.where((t) => appIsSelectableTrackId(t.id)).toList();

AppTrackSnapshot appSnapshotTracks(Player player) {
  final tracks = player.state.tracks;
  final cur = player.state.track;
  return AppTrackSnapshot(
    audios: appSelectableAudio(tracks),
    subtitles: appSelectableSubtitles(tracks),
    videos: appSelectableVideo(tracks),
    audio: cur.audio,
    subtitle: cur.subtitle,
    video: cur.video,
  );
}

String appAudioParts(AudioTrack t) {
  final parts = <String>[
    if ((t.language ?? '').trim().isNotEmpty) t.language!.trim(),
    if ((t.title ?? '').trim().isNotEmpty) t.title!.trim(),
    if ((t.channels ?? '').trim().isNotEmpty) t.channels!.trim(),
    if (t.audiochannels != null && t.audiochannels! > 0)
      '${t.audiochannels}ch',
  ];
  return parts.join(' · ');
}

String appSubtitleParts(SubtitleTrack t) {
  if (t.id == 'no') return '';
  final parts = <String>[
    if ((t.language ?? '').trim().isNotEmpty) t.language!.trim(),
    if ((t.title ?? '').trim().isNotEmpty) t.title!.trim(),
  ];
  return parts.join(' · ');
}

String appVideoParts(VideoTrack t) {
  final parts = <String>[
    if (t.h != null && t.h! > 0) '${t.h}p',
    if (t.w != null && t.h != null) '${t.w}×${t.h}',
    if ((t.title ?? '').trim().isNotEmpty) t.title!.trim(),
    if ((t.codec ?? '').trim().isNotEmpty) t.codec!.trim(),
  ];
  // Prefer a single resolution token when both h and w×h exist.
  if (t.h != null && t.h! > 0) {
    return [
      '${t.h}p',
      if ((t.title ?? '').trim().isNotEmpty) t.title!.trim(),
      if ((t.codec ?? '').trim().isNotEmpty) t.codec!.trim(),
    ].join(' · ');
  }
  return parts.join(' · ');
}

/// Match Settings → Audio preference to an embedded track when possible.
AudioTrack? appPreferAudio(List<AudioTrack> tracks, String? pref) {
  if (tracks.isEmpty || pref == null || pref.trim().isEmpty) return null;
  final p = pref.toLowerCase();

  bool hit(AudioTrack t, List<String> needles) {
    final blob =
        '${t.language ?? ''} ${t.title ?? ''} ${t.codec ?? ''} ${t.channels ?? ''}'
            .toLowerCase();
    return needles.any(blob.contains);
  }

  if (p.contains('atmos') || p.contains('dolby')) {
    final m = tracks.cast<AudioTrack?>().firstWhere(
          (t) => hit(t!, ['atmos', 'truehd', 'eac3', 'ddp', 'dolby']),
          orElse: () => null,
        );
    if (m != null) return m;
  }
  if (p.contains('stereo')) {
    final m = tracks.cast<AudioTrack?>().firstWhere(
          (t) =>
              (t!.channelscount != null && t.channelscount! <= 2) ||
              hit(t, ['stereo', '2.0', '2ch']),
          orElse: () => null,
        );
    if (m != null) return m;
  }
  if (p.contains('arabic')) {
    final m = tracks.cast<AudioTrack?>().firstWhere(
          (t) => hit(t!, ['ar', 'ara', 'arabic', 'عر']),
          orElse: () => null,
        );
    if (m != null) return m;
  }
  if (p.contains('english')) {
    final m = tracks.cast<AudioTrack?>().firstWhere(
          (t) => hit(t!, ['en', 'eng', 'english']),
          orElse: () => null,
        );
    if (m != null) return m;
  }
  return null;
}

/// Preferred subtitle languages (Settings copy: AR, EN, FR, ES, JA).
SubtitleTrack? appPreferSubtitle(
  List<SubtitleTrack> tracks, {
  List<String> langs = const ['ar', 'ara', 'en', 'eng', 'fr', 'es', 'ja', 'jpn'],
}) {
  if (tracks.isEmpty) return null;
  for (final lang in langs) {
    final needle = lang.toLowerCase();
    for (final t in tracks) {
      final blob = '${t.language ?? ''} ${t.title ?? ''}'.toLowerCase();
      if (blob.contains(needle)) return t;
    }
  }
  return tracks.first;
}
