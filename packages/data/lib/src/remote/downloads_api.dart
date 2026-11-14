import 'api_client.dart';
import 'api_exception.dart';
import 'json_read.dart';
import 'extras_api.dart' show DownloadQuotaDto;

/// Backend download grant (`/v1/downloads/*`, App-Backend Ali_branch).
///
/// [downloadUrl] carries the provider line credentials: keep it in memory
/// only, never persist or log it.
class DownloadGrantDto {
  const DownloadGrantDto({
    required this.grantId,
    required this.streamId,
    required this.contentType,
    required this.status,
    this.downloadUrl,
    this.containerExtension,
    this.title,
    this.bytesDownloaded = 0,
    this.bytesTotal,
    this.expiresAt,
    this.resumeSupported = true,
  });

  final String grantId;
  final String streamId;
  final String contentType;
  final String status;
  final String? downloadUrl;
  final String? containerExtension;
  final String? title;
  final int bytesDownloaded;
  final int? bytesTotal;
  final DateTime? expiresAt;
  final bool resumeSupported;

  factory DownloadGrantDto.fromJson(Map<String, dynamic> j) {
    int? asInt(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
    return DownloadGrantDto(
      grantId: '${j['grantId'] ?? ''}',
      streamId: '${j['streamId'] ?? ''}',
      contentType: '${j['contentType'] ?? 'vod'}',
      status: '${j['status'] ?? ''}',
      downloadUrl: jsonStr(j['downloadUrl']),
      containerExtension: jsonStr(j['containerExtension']),
      title: jsonStr(j['title']),
      bytesDownloaded: asInt(j['bytesDownloaded']) ?? 0,
      bytesTotal: asInt(j['bytesTotal']),
      expiresAt: DateTime.tryParse('${j['expiresAt'] ?? ''}'),
      resumeSupported: j['resumeSupported'] != false,
    );
  }
}

/// One download of a profile, on any of the account's devices (Usman
/// 13 Nov: `GET /v1/downloads?profileId=`). [state]: active / completed /
/// removed (removed in the panel: delete the local file).
class ProfileDownloadDto {
  const ProfileDownloadDto({
    required this.grantId,
    required this.deviceId,
    required this.contentType,
    required this.streamId,
    required this.state,
    this.deviceName,
    this.devicePlatform,
    this.profileId,
    this.seriesId,
    this.episodeId,
    this.title,
    this.posterUrl,
    this.sizeBytes,
    this.containerExtension,
    this.updatedAt,
  });

  final String grantId;
  final String deviceId;
  final String contentType;
  final String streamId;
  final String state;
  final String? deviceName;
  final String? devicePlatform;
  final String? profileId;
  final String? seriesId;
  final String? episodeId;
  final String? title;
  final String? posterUrl;
  final int? sizeBytes;
  final String? containerExtension;
  final DateTime? updatedAt;

  bool get isRemoved => state == 'removed';
  bool get isCompleted => state == 'completed';

  /// The stream to download (an episode's own stream id for series).
  String get playableId =>
      contentType == 'series' && (episodeId ?? '').isNotEmpty ? episodeId! : streamId;

  factory ProfileDownloadDto.fromJson(Map<String, dynamic> j) {
    int? asInt(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
    final status = '${j['status'] ?? ''}'.toUpperCase();
    var state = '${j['state'] ?? ''}'.toLowerCase();
    if (state.isEmpty) {
      state = status == 'CANCELLED'
          ? 'removed'
          : status == 'COMPLETED'
              ? 'completed'
              : 'active';
    }
    return ProfileDownloadDto(
      grantId: '${j['grantId'] ?? j['id'] ?? ''}',
      deviceId: '${j['deviceId'] ?? ''}',
      contentType: '${j['contentType'] ?? 'vod'}',
      streamId: '${j['streamId'] ?? ''}',
      state: state,
      deviceName: jsonStr(j['deviceName']),
      devicePlatform: jsonStr(j['devicePlatform']),
      profileId: jsonStr(j['profileId']),
      seriesId: jsonStr(j['seriesId']),
      episodeId: jsonStr(j['episodeId']),
      title: jsonStr(j['title']),
      posterUrl: jsonStr(j['posterUrl']),
      sizeBytes: asInt(j['sizeBytes']),
      containerExtension: jsonStr(j['containerExtension']),
      updatedAt: DateTime.tryParse('${j['updatedAt'] ?? ''}'),
    );
  }
}

class DownloadsApi {
  DownloadsApi(this._client);

  final ApiClient _client;

  /// PLAYBACK_ACTIVE_STOP_REQUIRED (409) when this device is playing and
  /// [stopPlaybackIfNeeded] is false; PLAYBACK_LEASE_HELD when another device
  /// plays. Live streams are rejected by the backend.
  Future<DownloadGrantDto> authorize({
    required String deviceId,
    required String contentType,
    required String streamId,
    String? containerExtension,
    String? title,
    String? profileId,
    String? seriesId,
    String? posterUrl,
    bool stopPlaybackIfNeeded = false,
  }) async {
    final data = await _client.post(
      '/downloads/authorize',
      body: {
        'deviceId': deviceId,
        'contentType': contentType,
        'streamId': streamId,
        if (containerExtension != null && containerExtension.isNotEmpty)
          'containerExtension': containerExtension,
        if (title != null && title.isNotEmpty) 'title': title,
        // Usman 13 Nov: the profile's downloads show on all its devices.
        if (profileId != null && profileId.isNotEmpty) 'profileId': profileId,
        if (seriesId != null && seriesId.isNotEmpty) 'seriesId': seriesId,
        if (posterUrl != null && posterUrl.isNotEmpty) 'posterUrl': posterUrl,
        'stopPlaybackIfNeeded': stopPlaybackIfNeeded,
      },
      auth: true,
    );
    if (data == null) throw ApiException('Empty download authorize response');
    return DownloadGrantDto.fromJson(data);
  }

  /// The profile's downloads on every device of the account, newest first
  /// (200 at most). Downloads from before 13 Nov have no profile and come
  /// for every profile.
  Future<List<ProfileDownloadDto>> forProfile(String profileId) async {
    final data = await _client.get(
      '/downloads',
      query: {'profileId': profileId},
      auth: true,
    );
    // A list answer arrives as {'_': [...]} (ApiClient); older shapes too.
    final list = data?['_'] ?? data?['items'] ?? data?['downloads'] ?? const [];
    if (list is! List) return const [];
    return [
      for (final e in list)
        if (e is Map) ProfileDownloadDto.fromJson(Map<String, dynamic>.from(e)),
    ];
  }

  Future<DownloadGrantDto> get(String grantId) async {
    final data = await _client.get('/downloads/$grantId', auth: true);
    if (data == null) throw ApiException('Download grant not found');
    return DownloadGrantDto.fromJson(data);
  }

  Future<void> progress(
    String grantId, {
    required String deviceId,
    required int bytesDownloaded,
    int? bytesTotal,
  }) async {
    await _client.post(
      '/downloads/$grantId/progress',
      body: {
        'deviceId': deviceId,
        'bytesDownloaded': bytesDownloaded,
        if (bytesTotal != null) 'bytesTotal': bytesTotal,
      },
      auth: true,
    );
  }

  Future<void> pause(String grantId, {required String deviceId}) =>
      _simple(grantId, 'pause', deviceId);

  Future<DownloadGrantDto> resume(
    String grantId, {
    required String deviceId,
  }) async {
    final data = await _client.post(
      '/downloads/$grantId/resume',
      body: {'deviceId': deviceId},
      auth: true,
    );
    if (data == null) throw ApiException('Empty download resume response');
    return DownloadGrantDto.fromJson(data);
  }

  Future<void> complete(String grantId, {required String deviceId}) =>
      _simple(grantId, 'complete', deviceId);

  Future<void> cancel(String grantId, {required String deviceId}) =>
      _simple(grantId, 'cancel', deviceId);

  Future<void> fail(
    String grantId, {
    required String deviceId,
    required String message,
  }) async {
    await _client.post(
      '/downloads/$grantId/fail',
      body: {
        'deviceId': deviceId,
        'message': message.length > 300 ? message.substring(0, 300) : message,
      },
      auth: true,
    );
  }

  /// Tells the server which downloads this device still holds; the others
  /// stop counting against the storage limit. Null on older servers.
  Future<DownloadQuotaDto?> reconcile({
    required String deviceId,
    required List<String> keepGrantIds,
  }) async {
    try {
      final data = await _client.post(
        '/downloads/reconcile',
        body: {'deviceId': deviceId, 'keepGrantIds': keepGrantIds},
        auth: true,
      );
      return DownloadQuotaDto.tryParse(data?['storage']);
    } catch (_) {
      return null;
    }
  }

  Future<void> _simple(String grantId, String action, String deviceId) async {
    await _client.post(
      '/downloads/$grantId/$action',
      body: {'deviceId': deviceId},
      auth: true,
    );
  }
}
