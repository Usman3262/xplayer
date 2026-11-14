import 'package:flutter/painting.dart';

/// How the picture is placed on the screen (client 21 Oct mobile #5: "does
/// not fit the full screen / looks cropped, especially Live TV and Sports").
///
/// Phones are ~20:9 and broadcast video is 16:9, so a single Fit/Zoom toggle
/// could only give side bars (Fit) or cut ~20 % off the top and bottom
/// (Zoom) — where sports score and clock graphics sit. [fill] fills the
/// whole screen without cutting anything; [ratio16x9] / [ratio4x3] force the
/// shape for channels that send a wrong aspect.
///
/// [stretch] (CEO 25 Oct, client's Strong 8K reference "تمدد"): the whole
/// picture on the whole screen, nothing cut; a 16:9 picture on a ~20:9 phone
/// is drawn about 22 % wider. It replaces the 23 Oct "no stretching" rule
/// and is the default for Live TV and Sports.
enum VideoScreenMode {
  fit,
  stretch,
  fill,
  zoom,
  ratio16x9,
  ratio4x3;

  static const prefKey = 'app_player_video_mode';

  /// Old two-way pref (true = Zoom), read once so a saved choice survives.
  static const legacyZoomPrefKey = 'app_player_video_zoom';

  static VideoScreenMode fromName(String? name, {bool? legacyZoom}) {
    for (final m in values) {
      if (m.name == name) return m;
    }
    return legacyZoom == true ? zoom : fit;
  }

  /// Chrome button cycle: the four that matter on a phone.
  VideoScreenMode get next => switch (this) {
        stretch => fit,
        fit => fill,
        fill => zoom,
        _ => stretch,
      };

  /// Live TV and Sports open in this mode unless changed on the channel.
  static const liveDefault = stretch;

  /// Fill scales proportionally until the screen is full (a 16:9 picture on
  /// a ~20:9 phone loses a little at the top and bottom); Zoom goes
  /// [zoomScale] closer. Fit shows it all with side bars. Stretch is the only
  /// mode that changes the proportions.
  BoxFit get boxFit => switch (this) {
        stretch => BoxFit.fill,
        fill || zoom => BoxFit.cover,
        _ => BoxFit.contain,
      };

  /// Extra proportional enlargement on top of [boxFit].
  double get extraScale => this == zoom ? zoomScale : 1.0;
  static const zoomScale = 1.2;

  /// Forced picture shape, or null to use the stream's own.
  double? get forcedAspect => switch (this) {
        ratio16x9 => 16 / 9,
        ratio4x3 => 4 / 3,
        _ => null,
      };

  /// True when the picture covers the whole [box].
  bool get coversScreen => this == stretch || this == fill || this == zoom;

  /// Where the picture is drawn inside [box] for a [videoSize] stream.
  Rect videoRect(Size box, Size videoSize) {
    final full = Offset.zero & box;
    if (coversScreen) return full;
    final ar = forcedAspect ??
        (videoSize.width > 0 && videoSize.height > 0
            ? videoSize.width / videoSize.height
            : 0);
    if (ar <= 0 || box.isEmpty) return full;
    var vw = box.width;
    var vh = vw / ar;
    if (vh > box.height) {
      vh = box.height;
      vw = vh * ar;
    }
    return Rect.fromLTWH((box.width - vw) / 2, (box.height - vh) / 2, vw, vh);
  }
}
