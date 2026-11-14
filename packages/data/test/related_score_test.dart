import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

/// Client 21 Oct (A14): "More Like This" must follow the title's genres and
/// category, not show the same list for every movie / series.
void main() {
  MediaItem m(String id, {List<String> genres = const [], String? cat, int? year, double? rating}) =>
      MediaItem(id: id, title: id, kind: MediaKind.movie, genres: genres, categoryId: cat, year: year, rating: rating);

  final base = m('base', genres: ['Action, Thriller'], cat: '10', year: 2022, rating: 7);

  double score(MediaItem other) => RemoteCatalogRepository.relatedScore(base, other);

  test('shared genres rank above unrelated titles', () {
    final action = m('a', genres: ['Action'], year: 2010);
    final comedy = m('c', genres: ['Comedy'], year: 2010, rating: 9.9);
    expect(score(action), greaterThan(score(comedy)));
  });

  test('same genre mix beats a partial match', () {
    final both = m('b', genres: ['Thriller', 'Action']);
    final one = m('o', genres: ['Action']);
    expect(score(both), greaterThan(score(one)));
  });

  test('same category and a close year add to the score', () {
    final sameCat = m('s', genres: ['Drama'], cat: '10', year: 2021);
    final otherCat = m('x', genres: ['Drama'], cat: '99', year: 1995);
    expect(score(sameCat), greaterThan(score(otherCat)));
  });

  test('different titles get different lists (not one fixed list)', () {
    final horror = m('h', genres: ['Horror']);
    final family = m('f', genres: ['Family']);
    final horrorBase = m('hb', genres: ['Horror']);
    final familyBase = m('fb', genres: ['Family']);
    expect(RemoteCatalogRepository.relatedScore(horrorBase, horror), greaterThan(RemoteCatalogRepository.relatedScore(horrorBase, family)));
    expect(RemoteCatalogRepository.relatedScore(familyBase, family), greaterThan(RemoteCatalogRepository.relatedScore(familyBase, horror)));
  });
}
