import 'api_client.dart';
import 'api_exception.dart';
import 'media_models.dart';
import '../security/device_attestation.dart';
import '../security/device_pop.dart';

class PlaybackApi {
  PlaybackApi(this._client);

  final ApiClient _client;

  /// Read-only Active/Inactive lease for Settings (M2 Usman handoff).
  Future<PlaybackLeaseStatusDto> leaseStatus() async {
    final data = await _client.get('/playback/lease', auth: true);
    if (data == null) {
      return const PlaybackLeaseStatusDto(
        status: 'Inactive',
        label: '0/1',
        active: 0,
        max: 1,
      );
    }
    return PlaybackLeaseStatusDto.fromJson(data);
  }

  Future<PlaybackActiveDto> active() async {
    final data = await _client.get('/playback/active', auth: true);
    if (data == null) {
      return const PlaybackActiveDto(active: false);
    }
    return PlaybackActiveDto.fromJson(data);
  }

  Future<PlaybackSessionDto> start({
    required String deviceId,
    required String contentType,
    required String streamId,
    String? profileId,
    String? containerExtension,
    int? maxHeight,
    String? tier,
    List<String>? codecs,
    bool force = false,
    String? title,
    String? categoryName,
  }) async {
    final body = <String, dynamic>{
      'deviceId': deviceId,
      'contentType': contentType,
      'streamId': streamId,
    };
    if (force) body['force'] = true;
    if (profileId != null && profileId.isNotEmpty) {
      body['profileId'] = profileId;
    }
    if (containerExtension != null && containerExtension.isNotEmpty) {
      body['containerExtension'] = containerExtension;
    }
    if (maxHeight != null && maxHeight > 0) {
      body['maxHeight'] = maxHeight;
    }
    if (tier != null && tier.isNotEmpty) {
      body['tier'] = tier;
    }
    if (codecs != null && codecs.isNotEmpty) {
      body['codecs'] = codecs;
    }
    // What the customer sees, for the Control Panel (client 27 Oct).
    if (title != null && title.trim().isNotEmpty) body['title'] = title.trim();
    if (categoryName != null && categoryName.trim().isNotEmpty) {
      body['categoryName'] = categoryName.trim();
    }
    // Block mode: ATTESTATION_REQUIRED -> attest once, retry once.
    final data = await DeviceAttestation.retryIfRequired(
      _client,
      deviceId,
      () => DevicePop.post(
        _client,
        '/playback/start',
        body: body,
        auth: true,
        proof: () => DevicePop.forDevice(_client, deviceId),
      ),
    );
    if (data == null) throw ApiException('Empty playback start response');
    return PlaybackSessionDto.fromJson(data);
  }

  /// Force-start (take over other device lease). Same body as start; force implied.
  Future<PlaybackSessionDto> takeover({
    required String deviceId,
    required String contentType,
    required String streamId,
    String? profileId,
    String? containerExtension,
    int? maxHeight,
    String? tier,
    List<String>? codecs,
    String? title,
    String? categoryName,
  }) async {
    final body = <String, dynamic>{
      'deviceId': deviceId,
      'contentType': contentType,
      'streamId': streamId,
    };
    if (profileId != null && profileId.isNotEmpty) {
      body['profileId'] = profileId;
    }
    if (containerExtension != null && containerExtension.isNotEmpty) {
      body['containerExtension'] = containerExtension;
    }
    if (maxHeight != null && maxHeight > 0) {
      body['maxHeight'] = maxHeight;
    }
    if (tier != null && tier.isNotEmpty) {
      body['tier'] = tier;
    }
    if (codecs != null && codecs.isNotEmpty) {
      body['codecs'] = codecs;
    }
    // What the customer sees, for the Control Panel (client 27 Oct).
    if (title != null && title.trim().isNotEmpty) body['title'] = title.trim();
    if (categoryName != null && categoryName.trim().isNotEmpty) {
      body['categoryName'] = categoryName.trim();
    }
    // Block mode: ATTESTATION_REQUIRED -> attest once, retry once.
    final data = await DeviceAttestation.retryIfRequired(
      _client,
      deviceId,
      () => DevicePop.post(
        _client,
        '/playback/takeover',
        body: body,
        auth: true,
        proof: () => DevicePop.forDevice(_client, deviceId),
      ),
    );
    if (data == null) throw ApiException('Empty playback takeover response');
    return PlaybackSessionDto.fromJson(data);
  }

  Future<PlaybackSessionDto> heartbeat({
    required String playbackId,
    required String deviceId,
    Map<String, Object?>? stats,
    bool? paused,
  }) async {
    final data = await _client.post(
      '/playback/$playbackId/heartbeat',
      // paused: the Control Panel shows "Paused" (Usman 13 Nov).
      body: {'deviceId': deviceId, 'stats': ?stats, 'paused': ?paused},
      auth: true,
    );
    if (data == null) throw ApiException('Empty playback heartbeat response');
    return PlaybackSessionDto.fromJson(data);
  }

  Future<PlaybackSessionDto> stop({
    required String playbackId,
    required String deviceId,
  }) async {
    final data = await _client.post(
      '/playback/$playbackId/stop',
      body: {'deviceId': deviceId},
      auth: true,
    );
    if (data == null) {
      return PlaybackSessionDto(
        playbackId: playbackId,
        contentType: '',
        streamId: '',
        playUrl: '',
        status: 'STOPPED',
      );
    }
    return PlaybackSessionDto.fromJson(data);
  }

  /// Fire-and-forget playback report (open ok / failed / mid-play failure).
  /// The body must already be scrubbed; see [DiagTrail].
  Future<void> report(Map<String, Object?> body) async {
    await _client.post('/playback/report', body: body, auth: true);
  }
}
