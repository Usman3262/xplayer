import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'api_exception.dart';
import 'auth_models.dart';
import 'media_models.dart';

class ProfilesApi {
  ProfilesApi(this._client);

  final ApiClient _client;

  Future<List<ProfileDto>> list() async {
    final data = await _client.get('/profiles', auth: true);
    return unwrapListData(data).map(ProfileDto.fromJson).toList();
  }

  Future<ProfileDto> create({
    required String name,
    String? avatarUrl,
    bool isKids = false,
  }) async {
    final body = <String, dynamic>{
      'name': name.trim(),
      'isKids': isKids,
    };
    if (avatarUrl != null) body['avatarUrl'] = avatarUrl;
    final data = await _client.post('/profiles', body: body, auth: true);
    if (data == null) throw ApiException('Empty profile create response');
    return ProfileDto.fromJson(data);
  }

  Future<ProfileDto> update({
    required String id,
    String? name,
    String? avatarUrl,
    bool? isKids,
    bool? pinLocked,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name.trim();
    if (avatarUrl != null) body['avatarUrl'] = avatarUrl;
    if (isKids != null) body['isKids'] = isKids;
    if (pinLocked != null) body['pinLocked'] = pinLocked;
    final data = await _client.patch('/profiles/$id', body: body, auth: true);
    if (data == null) throw ApiException('Empty profile update response');
    return ProfileDto.fromJson(data);
  }

  Future<void> delete(String id) async {
    await _client.delete('/profiles/$id', auth: true);
  }

  Future<void> saveProgress({
    required String profileId,
    required String contentType,
    required String streamId,
    String? seriesId,
    String? episodeId,
    required String title,
    String? posterUrl,
    required int positionSec,
    required int durationSec,
  }) async {
    await _client.put(
      '/profiles/$profileId/progress',
      body: {
        'contentType': contentType,
        'streamId': streamId,
        'seriesId': seriesId,
        'episodeId': episodeId,
        'title': title,
        'posterUrl': posterUrl,
        'positionSec': positionSec,
        'durationSec': durationSec,
      },
      auth: true,
    );
  }

  Future<List<ContinueWatchingDto>> continueWatching(String profileId) async {
    final data =
        await _client.get('/profiles/$profileId/continue-watching', auth: true);
    return _parseContinueWatchingAsync(data);
  }

  Future<List<ContinueWatchingDto>> history(String profileId) async {
    final data = await _client.get('/profiles/$profileId/history', auth: true);
    return _parseContinueWatchingAsync(data);
  }

  Future<List<ProfileLibraryItemDto>> favorites(String profileId) async {
    final data =
        await _client.get('/profiles/$profileId/favorites', auth: true);
    return _parseLibraryItemsAsync(data);
  }

  Future<void> addFavorite({
    required String profileId,
    required String contentType,
    required String streamId,
    String? seriesId,
    required String title,
    String? posterUrl,
    String? categoryId,
  }) async {
    await _client.post(
      '/profiles/$profileId/favorites',
      body: {
        'contentType': contentType,
        'streamId': streamId,
        'seriesId': seriesId,
        'title': title,
        'posterUrl': posterUrl,
        if (categoryId != null && categoryId.isNotEmpty) 'categoryId': categoryId,
      },
      auth: true,
    );
  }

  Future<void> removeFavorite({
    required String profileId,
    required String contentType,
    required String streamId,
  }) async {
    await _client.delete(
      '/profiles/$profileId/favorites/$contentType/$streamId',
      auth: true,
    );
  }

  Future<List<ProfileLibraryItemDto>> myList(String profileId) async {
    final data = await _client.get('/profiles/$profileId/my-list', auth: true);
    return _parseLibraryItemsAsync(data);
  }

  Future<void> addMyList({
    required String profileId,
    required String contentType,
    required String streamId,
    String? seriesId,
    required String title,
    String? posterUrl,
  }) async {
    await _client.post(
      '/profiles/$profileId/my-list',
      body: {
        'contentType': contentType,
        'streamId': streamId,
        'seriesId': seriesId,
        'title': title,
        'posterUrl': posterUrl,
      },
      auth: true,
    );
  }

  Future<void> removeMyList({
    required String profileId,
    required String contentType,
    required String streamId,
  }) async {
    await _client.delete(
      '/profiles/$profileId/my-list/$contentType/$streamId',
      auth: true,
    );
  }

  Future<List<ContinueWatchingDto>> _parseContinueWatchingAsync(
    Map<String, dynamic>? data,
  ) async {
    final rows = unwrapListData(data);
    if (rows.length < 10) {
      return rows.map(ContinueWatchingDto.fromJson).toList();
    }
    return compute(_continueWatchingIsolate, data);
  }

  Future<List<ProfileLibraryItemDto>> _parseLibraryItemsAsync(
    Map<String, dynamic>? data,
  ) async {
    final rows = unwrapListData(data);
    if (rows.length < 10) {
      return rows.map(ProfileLibraryItemDto.fromJson).toList();
    }
    return compute(_libraryItemsIsolate, data);
  }
}

List<ContinueWatchingDto> _continueWatchingIsolate(Map<String, dynamic>? data) =>
    unwrapListData(data).map(ContinueWatchingDto.fromJson).toList();

List<ProfileLibraryItemDto> _libraryItemsIsolate(Map<String, dynamic>? data) =>
    unwrapListData(data).map(ProfileLibraryItemDto.fromJson).toList();
