import 'api_client.dart';
import 'api_exception.dart';
import 'auth_models.dart';
import '../security/device_pop.dart';

class DevicesApi {
  DevicesApi(this._client);

  final ApiClient _client;
  Future<DeviceDto> register({
    required String platform,
    required String name,
    String? publicKey,
    Map<String, dynamic>? deviceCaps,
  }) async {
    final body = <String, dynamic>{
      'platform': platform,
      'name': name,
    };
    if (publicKey != null && publicKey.isNotEmpty) {
      body['publicKey'] = publicKey;
    }
    if (deviceCaps != null && deviceCaps.isNotEmpty) {
      body['deviceCaps'] = deviceCaps;
    }
    final data = await _client.post(
      '/devices/register',
      body: body,
      auth: true,
    );
    if (data == null) throw ApiException('Empty device register response');
    return DeviceDto.fromJson(data);
  }

  Future<List<DeviceDto>> list({String? status}) async {
    final query = status == null || status.isEmpty
        ? null
        : {'status': status};
    final data = await _client.get('/devices', auth: true, query: query);
    return unwrapListData(data).map(DeviceDto.fromJson).toList();
  }

  Future<DeviceDto> rename({
    required String deviceId,
    required String name,
  }) async {
    final data = await _client.post(
      '/devices/$deviceId/rename',
      body: {'name': name.trim()},
      auth: true,
    );
    if (data == null) throw ApiException('Empty device rename response');
    return DeviceDto.fromJson(data);
  }

  Future<void> revoke(String deviceId) async {
    await _client.post('/devices/$deviceId/revoke', auth: true);
  }

  Future<DeviceDto> setPriority(String deviceId) async {
    final data = await _client.post(
      '/devices/$deviceId/set-priority',
      auth: true,
    );
    if (data == null) throw ApiException('Empty set-priority response');
    return DeviceDto.fromJson(data);
  }

  Future<void> clearPriority() async {
    await _client.delete('/devices/priority', auth: true);
  }

  Future<RevokeAllDevicesResult> revokeAll({
    bool keepCurrentDevice = true,
    String? password,
  }) async {
    final body = <String, dynamic>{
      'keepCurrentDevice': keepCurrentDevice,
    };
    if (password != null && password.isNotEmpty) {
      body['password'] = password;
    }
    final data = await _client.post(
      '/devices/revoke-all',
      body: body,
      auth: true,
    );
    if (data == null) {
      return const RevokeAllDevicesResult(revokedDeviceCount: 0);
    }
    return RevokeAllDevicesResult.fromJson(data);
  }

  Future<void> registerPushToken({
    required String deviceId,
    required String token,
    String provider = 'FCM',
  }) async {
    await _client.post(
      '/devices/$deviceId/push-token',
      body: {
        'token': token,
        'provider': provider,
      },
      auth: true,
    );
  }

  /// Keep lastSeenAt fresh so priority can become STALE / unreachable.
  Future<void> heartbeat({
    required String deviceId,
    String? trustedDeviceId,
    required String platform,
    String? appVersion,
    String? osVersion,
  }) async {
    final body = <String, dynamic>{
      'deviceId': deviceId,
      'platform': platform,
    };
    if (osVersion != null && osVersion.isNotEmpty) body['osVersion'] = osVersion;
    if (trustedDeviceId != null && trustedDeviceId.isNotEmpty) {
      body['trustedDeviceId'] = trustedDeviceId;
    }
    if (appVersion != null && appVersion.isNotEmpty) {
      body['appVersion'] = appVersion;
    }
    await _client.post('/devices/me/heartbeat', body: body, auth: true);
  }

  /// Result of the in-app connection test, shown in the Control Panel.
  Future<void> reportSpeed({required String deviceId, required double mbps}) async {
    await _client.post(
      '/devices/me/speed-test',
      body: {'deviceId': deviceId, 'mbps': double.parse(mbps.toStringAsFixed(1))},
      auth: true,
    );
  }

  /// `POST /devices/{id}/pop/key` — idempotent for the same public key.
  Future<void> registerPopKey(String deviceId) =>
      DevicePop.ensureEnrolled(_client, deviceId);
}
