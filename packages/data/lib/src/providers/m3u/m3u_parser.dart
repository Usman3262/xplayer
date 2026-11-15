import 'dart:convert';

import 'package:crypto/crypto.dart' show sha1;
import 'package:domain/domain.dart';

/// One playlist entry, exactly as the file describes it.
class M3uEntry {
  const M3uEntry({
    required this.title,
    required this.url,
    this.attributes = const {},
    this.headers = const {},
    this.group,
    this.duration = -1,
  });

  final String title;
  final String url;

  /// `tvg-id`, `tvg-name`, `tvg-logo`, `group-title`, `tvg-chno`, `catchup-days` …
  /// (keys lower-cased).
  final Map<String, String> attributes;

  /// From `#EXTVLCOPT:http-user-agent=` / `http-referrer=` / `#KODIPROP` headers.
  final Map<String, String> headers;

  /// `group-title`, else `#EXTGRP:`.
  final String? group;
  final int duration;

  String? attr(String key) {
    final v = attributes[key]?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }
}

class M3uPlaylist {
  const M3uPlaylist({required this.entries, this.epgUrls = const [], this.hadHeader = false});

  final List<M3uEntry> entries;

  /// From the header `url-tvg` / `x-tvg-url` (may list several).
  final List<String> epgUrls;

  /// File started with `#EXTM3U`.
  final bool hadHeader;
}

final _attr = RegExp(r'([A-Za-z0-9_\-]+)\s*=\s*"([^"]*)"');

/// Tolerant M3U / M3U8 parser (BOM, CRLF, missing header, commas inside
/// attribute values, options between #EXTINF and the URL). Duplicate URLs are
/// dropped; source order is kept. Runs in an isolate for big playlists.
M3uPlaylist parseM3u(String text) {
  var src = text;
  if (src.startsWith('﻿')) src = src.substring(1);
  final lines = src.split(RegExp(r'\r\n|\r|\n'));

  var hadHeader = false;
  final epg = <String>[];
  final out = <M3uEntry>[];
  final seenUrls = <String>{};

  String? title;
  var attrs = <String, String>{};
  var headers = <String, String>{};
  String? extGroup;
  var duration = -1;

  void reset() {
    title = null;
    attrs = {};
    headers = {};
    extGroup = null;
    duration = -1;
  }

  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('#EXTM3U')) {
      hadHeader = true;
      for (final m in _attr.allMatches(line)) {
        final k = m.group(1)!.toLowerCase();
        if (k == 'url-tvg' || k == 'x-tvg-url') {
          epg.addAll(m.group(2)!.split(',').map((s) => s.trim()).where((s) => s.startsWith('http')));
        }
      }
      continue;
    }
    if (line.startsWith('#EXTINF:')) {
      reset();
      final body = line.substring(8);
      final durMatch = RegExp(r'^\s*(-?\d+(\.\d+)?)').firstMatch(body);
      duration = durMatch == null ? -1 : double.parse(durMatch.group(1)!).round();
      var lastAttrEnd = durMatch?.end ?? 0;
      for (final m in _attr.allMatches(body)) {
        attrs[m.group(1)!.toLowerCase()] = m.group(2)!;
        lastAttrEnd = m.end;
      }
      final comma = body.indexOf(',', lastAttrEnd);
      title = comma < 0 ? '' : body.substring(comma + 1).trim();
      continue;
    }
    if (line.startsWith('#EXTGRP:')) {
      extGroup = line.substring(8).trim();
      continue;
    }
    if (line.startsWith('#EXTVLCOPT:')) {
      final opt = line.substring(11);
      final eq = opt.indexOf('=');
      if (eq > 0) {
        final k = opt.substring(0, eq).trim().toLowerCase();
        final v = opt.substring(eq + 1).trim();
        if (k == 'http-user-agent') headers['User-Agent'] = v;
        if (k == 'http-referrer' || k == 'http-referer') headers['Referer'] = v;
        if (k == 'http-origin') headers['Origin'] = v;
      }
      continue;
    }
    if (line.startsWith('#KODIPROP:')) {
      // inputstream.adaptive.stream_headers=User-Agent=…&Referer=…
      final m = RegExp(r'stream_headers=(.+)$').firstMatch(line);
      if (m != null) {
        for (final pair in m.group(1)!.split('&')) {
          final eq = pair.indexOf('=');
          if (eq > 0) headers[Uri.decodeComponent(pair.substring(0, eq))] = Uri.decodeComponent(pair.substring(eq + 1));
        }
      }
      continue;
    }
    if (line.startsWith('#')) continue; // other directives / comments

    // A URL line ends the entry (an URL without #EXTINF still counts).
    final url = line;
    if (!(url.startsWith('http://') || url.startsWith('https://') || url.startsWith('rtmp') || url.startsWith('rtsp'))) {
      reset();
      continue;
    }
    if (seenUrls.add(url)) {
      final group = (attrs['group-title']?.trim().isNotEmpty ?? false) ? attrs['group-title']!.trim() : extGroup;
      final t = (title ?? '').isNotEmpty ? title! : (attrs['tvg-name'] ?? '');
      out.add(M3uEntry(
        title: t,
        url: url,
        attributes: attrs,
        headers: headers,
        group: (group == null || group.isEmpty) ? null : group,
        duration: duration,
      ));
    }
    reset();
  }
  return M3uPlaylist(entries: out, epgUrls: epg, hadHeader: hadHeader);
}

const _vodExtensions = {'mp4', 'mkv', 'avi', 'mov', 'm4v', 'webm', 'wmv', 'flv', 'mpg', 'mpeg'};
final _sxe = RegExp(r'\bS(\d{1,2})\s*[ ._-]?\s*E(\d{1,3})\b', caseSensitive: false);

/// Live / movie / series episode, from the URL shape (Xtream-style
/// `/movie/` `/series/` paths, file extension) and an "S01E02" title.
MediaKind m3uKindOf(M3uEntry e) {
  final path = Uri.tryParse(e.url)?.path.toLowerCase() ?? '';
  if (path.contains('/series/')) return MediaKind.series;
  if (path.contains('/movie/')) return MediaKind.movie;
  if (path.contains('/live/')) return MediaKind.live;
  final dot = path.lastIndexOf('.');
  final ext = dot < 0 ? '' : path.substring(dot + 1);
  if (_vodExtensions.contains(ext)) {
    return _sxe.hasMatch(e.title) ? MediaKind.series : MediaKind.movie;
  }
  return MediaKind.live;
}

/// "Show Name S01 E02 - Pilot" → (Show Name, 1, 2). Null when there's no SxxEyy.
({String show, int season, int episode})? m3uEpisodeInfo(String title) {
  final m = _sxe.firstMatch(title);
  if (m == null) return null;
  final show = title.substring(0, m.start).replaceAll(RegExp(r'[\s\-–:|.]+$'), '').trim();
  return (show: show.isEmpty ? title.trim() : show, season: int.parse(m.group(1)!), episode: int.parse(m.group(2)!));
}

/// Stable short id for an entry without a panel id (works on web too).
String m3uStableId(String s) => sha1.convert(utf8.encode(s)).toString().substring(0, 16);

/// Id from an Xtream-style URL ending `/123.ts`, else a hash of the URL.
String m3uEntryId(M3uEntry e) {
  final m = RegExp(r'/(\d+)(\.[A-Za-z0-9]{2,5})?$').firstMatch(Uri.tryParse(e.url)?.path ?? '');
  return m?.group(1) ?? m3uStableId(e.url);
}
