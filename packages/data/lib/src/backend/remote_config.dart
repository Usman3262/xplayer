// Remote app configuration (`get_app_config`). Parsed leniently: bad or unknown
// fields are dropped, never thrown, so a broken admin edit can't crash the app.
// Keep the last valid [RemoteConfig] cached on the device (see [RemoteConfig.toJson]).

import '../remote/json_read.dart';
import 'home_layout.dart';
import 'json_util.dart';

enum AuthMode { optional, required, disabled }

enum UpdateRequirement { none, recommended, required }

class VersionPolicy {
  const VersionPolicy({this.min, this.recommended, this.latest, this.updateUrl, this.notes});

  final String? min;
  final String? recommended;
  final String? latest;
  final String? updateUrl;
  final String? notes;

  UpdateRequirement check(String appVersion) {
    if (min != null && compareAppVersion(appVersion, min!) < 0) return UpdateRequirement.required;
    if (recommended != null && compareAppVersion(appVersion, recommended!) < 0) {
      return UpdateRequirement.recommended;
    }
    return UpdateRequirement.none;
  }

  factory VersionPolicy.fromJson(Map<String, dynamic> j) => VersionPolicy(
        min: jsonStr(j['min']),
        recommended: jsonStr(j['recommended']),
        latest: jsonStr(j['latest']),
        updateUrl: jsonStr(j['url']),
        notes: jsonStr(j['notes']),
      );
}

class MaintenanceNotice {
  const MaintenanceNotice({required this.title, required this.message, this.until});
  final String title;
  final String message;
  final DateTime? until;

  static MaintenanceNotice? tryParse(Object? v) {
    final j = jsonMap(v);
    final title = jsonStr(j['title']);
    final message = jsonStr(j['message']);
    if (title == null || message == null) return null;
    return MaintenanceNotice(title: title, message: message, until: jsonDate(j['to']));
  }
}

/// One field of a "Choose your panel" connect form.
class PanelField {
  const PanelField({
    required this.key,
    required this.type,
    required this.label,
    this.placeholder,
    this.required = false,
  });

  final String key;

  /// text | password | url | mac | number (unknown → text).
  final String type;
  final String label;
  final String? placeholder;
  final bool required;

  static PanelField? tryParse(Map<String, dynamic> j) {
    final key = jsonStr(j['key']);
    final label = jsonStr(j['label']);
    if (key == null || label == null) return null;
    const known = {'text', 'password', 'url', 'mac', 'number'};
    final type = jsonStr(j['type']);
    return PanelField(
      key: key,
      label: label,
      type: known.contains(type) ? type! : 'text',
      placeholder: jsonStr(j['placeholder']),
      required: jsonBool(j['required']) ?? false,
    );
  }
}

/// A panel type on the "Choose your panel" screen (xtream, m3u, stalker, …).
class PanelType {
  const PanelType({
    required this.key,
    required this.label,
    this.description,
    this.help,
    this.icon,
    this.fields = const [],
  });

  final String key;
  final String label;
  final String? description;
  final String? help;
  final String? icon;
  final List<PanelField> fields;

  static PanelType? tryParse(Map<String, dynamic> j) {
    final key = jsonStr(j['key']);
    final label = jsonStr(j['label']);
    if (key == null || label == null) return null;
    return PanelType(
      key: key,
      label: label,
      description: jsonStr(j['description']),
      help: jsonStr(j['help']),
      icon: jsonStr(j['icon']),
      fields: jsonMapList(j['fields']).map(PanelField.tryParse).whereType<PanelField>().toList(),
    );
  }
}

class RemoteConfig {
  const RemoteConfig({
    required this.version,
    this.publishedAt,
    this.settings = const {},
    this.flags = const {},
    this.versionPolicy,
    this.maintenance,
    this.panelTypes = const [],
    this.theme = const {},
    this.home = HomeLayout.empty,
    this.raw = const {},
  });

  /// Published config version (0 = nothing published yet).
  final int version;
  final DateTime? publishedAt;
  final Map<String, dynamic> settings;
  final Map<String, bool> flags;
  final VersionPolicy? versionPolicy;
  final MaintenanceNotice? maintenance;
  final List<PanelType> panelTypes;

  /// Colour tokens for `AppThemeConfig.applyJson` (keys like "primary": "#22D3EE").
  final Map<String, String> theme;
  final HomeLayout home;

  /// Original JSON, for caching on the device.
  final Map<String, dynamic> raw;

  static const empty = RemoteConfig(version: 0);

  // ── typed settings with defaults ──────────────────────────────────────────
  bool boolSetting(String key, bool fallback) => jsonBool(settings[key]) ?? fallback;
  int intSetting(String key, int fallback) => jsonInt(settings[key]) ?? fallback;
  String stringSetting(String key, String fallback) => jsonStr(settings[key]) ?? fallback;
  List<String> listSetting(String key, List<String> fallback) =>
      settings[key] is List ? jsonStrList(settings[key]) : fallback;

  /// Unknown flags use [fallback] (an app newer than the config).
  bool isEnabled(String flag, {bool fallback = true}) => flags[flag] ?? fallback;

  AuthMode get authMode =>
      jsonEnum(settings['auth.mode'], AuthMode.values, AuthMode.optional);

  Map<String, dynamic> toJson() => raw;

  /// Parses a full reply. Returns null for "unchanged" replies or junk.
  static RemoteConfig? tryParse(Object? json) {
    final j = jsonMap(json);
    final version = jsonInt(j['version']);
    if (version == null || jsonBool(j['unchanged']) == true) return null;

    final flags = <String, bool>{};
    jsonMap(j['flags']).forEach((k, v) {
      final b = jsonBool(v);
      if (b != null) flags[k] = b;
    });
    final theme = <String, String>{};
    jsonMap(j['theme']).forEach((k, v) {
      final s = jsonStr(v);
      if (s != null) theme[k] = s;
    });
    final policy = j['version_policy'];

    return RemoteConfig(
      version: version,
      publishedAt: jsonDate(j['published_at']),
      settings: jsonMap(j['settings']),
      flags: flags,
      versionPolicy: policy is Map ? VersionPolicy.fromJson(jsonMap(policy)) : null,
      maintenance: MaintenanceNotice.tryParse(j['maintenance']),
      panelTypes: jsonMapList(j['onboarding']).map(PanelType.tryParse).whereType<PanelType>().toList(),
      theme: theme,
      home: HomeLayout.fromJson(jsonMap(j['home'])),
      raw: j,
    );
  }

  /// True when [json] is the short "you already have it" reply.
  static bool isUnchanged(Object? json) => jsonBool(jsonMap(json)['unchanged']) == true;
}
