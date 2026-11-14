import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  MediaItem m(String id, String t, {List<String> badges = const []}) =>
      MediaItem(id: id, title: t, kind: MediaKind.movie, badges: badges);

  test('finds the HD copy of a 4K movie', () {
    final uhd = m('768292', 'صقر وكناريا', badges: ['4K']);
    final hd = m('768100', 'صقر وكناريا');
    final other = m('1', 'صقر');
    expect(pickHdAlternative(uhd, [uhd, other, hd])?.id, '768100');
  });

  test('ignores other 4K copies and different titles', () {
    final uhd = m('1', 'Dune Part Two (2024)', badges: ['4K']);
    expect(pickHdAlternative(uhd, [m('2', 'Dune Part Two (2024) 4K'), m('3', 'Dune (2021)')]), isNull);
    expect(pickHdAlternative(uhd, [m('4', 'Dune Part Two (2024)')])?.id, '4');
  });

  test('quality and country prefixes do not block a match', () {
    expect(comparableTitle('4K-AR: صقر وكناريا'), comparableTitle('AR: صقر وكناريا'));
  });
}
