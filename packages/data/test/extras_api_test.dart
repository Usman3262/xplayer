import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('EPG row parses ISO times and rejects incomplete rows', () {
    final p = EpgProgramDto.tryParse({
      'title': 'Match',
      'startAt': '2026-10-16T18:00:00.000Z',
      'endAt': '2026-10-16T20:00:00.000Z',
    })!;
    expect(p.title, 'Match');
    expect(p.isOnAt(DateTime.utc(2026, 10, 16, 19).toLocal()), isTrue);
    expect(p.isOnAt(DateTime.utc(2026, 10, 16, 20).toLocal()), isFalse);
    expect(EpgProgramDto.tryParse({'title': 'x', 'startAt': 'bad'}), isNull);
  });

  // Client 18 Oct #9: sports packages were listed first in general Live TV.
  // The backend flag only knows "sport" in the name and its id allowlist, so
  // its false is not a veto: a package flagged or named as sports is sports.
  test('live category sports: backend flag or the sports name rule', () {
    final flagged = CatalogCategoryDto.fromJson(
      {'id': '9', 'name': 'AL-KASS', 'isSports': true},
    );
    final old = CatalogCategoryDto.fromJson({'id': '1', 'name': 'AL-KASS'});
    expect(flagged.isSports, isTrue);
    expect(old.isSports, isNull);
    expect(
      RemoteCatalogRepository.isSportsCategory(
        const CatalogCategory(id: '9', name: 'AL-KASS', isSports: true),
      ),
      isTrue,
    );
    expect(
      RemoteCatalogRepository.isSportsCategory(
        const CatalogCategory(id: '1', name: 'AL-KASS'),
      ),
      isTrue,
    );
    expect(
      RemoteCatalogRepository.isSportsCategory(
        const CatalogCategory(id: '4', name: 'MBC DRAMA', isSports: false),
      ),
      isFalse,
    );
    expect(
      RemoteCatalogRepository.isSportsCategory(
        const CatalogCategory(id: '2', name: 'BEIN SPORTS HD'),
      ),
      isTrue,
    );
    expect(
      RemoteCatalogRepository.isSportsCategory(
        const CatalogCategory(id: '3', name: 'beIN SPORTS', isSports: false),
      ),
      isTrue,
    );
  });

  test('VOD info keeps empty fields null', () {
    final v = VodInfoDto.fromJson({
      'vodId': '5',
      'plot': '  ',
      'cast': 'A, B',
      'durationSec': 5400,
      'genres': ['Drama'],
    });
    expect(v.plot, isNull);
    expect(v.cast, 'A, B');
    expect(v.durationSec, 5400);
    expect(v.genres, ['Drama']);
  });

  test('VOD info normalizes minute-valued durationSec and clock strings', () {
    final mins = VodInfoDto.fromJson({'vodId': '1', 'durationSec': 120});
    expect(mins.durationSec, 7200);
    final clock = VodInfoDto.fromJson({
      'vodId': '2',
      'duration': '01:45:00',
      'durationSec': 2,
    });
    expect(clock.durationSec, 6300);
  });

  test('reminder row with and without programme time', () {
    final t = ReminderDto.fromJson({'contentType': 'vod', 'streamId': '7'});
    final p = ReminderDto.fromJson({
      'contentType': 'live',
      'streamId': '8',
      'startsAt': '2026-10-16T18:00:00.000Z',
      'programTitle': 'News',
    });
    expect(t.startsAt, isNull);
    expect(p.startsAt, isNotNull);
    expect(p.programTitle, 'News');
  });

  test('sports entitlement refusal has a clear message', () {
    final e = ApiException(
      'Sports is not included in this package',
      statusCode: 403,
      code: 'SPORTS_NOT_ENTITLED',
    );
    expect(
      userFacingPlaybackError(e),
      'Sports is not included in your package.',
    );
  });

  test('C2: no-access-token / session errors map to sign-in copy', () {
    expect(
      userFacingPlaybackError(
        ApiException(
          'No access token stored. Please sign in again.',
          statusCode: 401,
        ),
      ),
      'Please sign in again.',
    );
    expect(
      userFacingPlaybackError(
        ApiException('Session expired. Please sign in again.', statusCode: 401),
      ),
      'Please sign in again.',
    );
    expect(
      sanitizeUserFacingError('.No access token stored. Please sign in again.'),
      'No access token stored. Please sign in again.',
    );
  });
}
