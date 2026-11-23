import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/features/visible_range/model/visible_range_pin_split.dart';
import 'package:aves/model/filters/container/set_or.dart';
import 'package:aves/model/filters/favourite.dart';
import 'package:aves/model/filters/mime.dart';
import 'package:aves/model/filters/path.dart';
import 'package:aves/model/filters/rating.dart';
import 'package:aves/services/common/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// The pin split must reproduce the media set when it is followed literally:
/// a source-only union becomes parallel sources, every other positive source
/// stays one conjunctive source, and the rest becomes restrictions.
void main() {
  late PathFilter albumA;
  late PathFilter albumB;

  setUpAll(() {
    getIt.registerLazySingleton<p.Context>(() => p.Context(style: p.Style.posix));
    albumA = PathFilter('/a');
    albumB = PathFilter('/b');
  });

  tearDownAll(getIt.reset);

  const favourite = FavouriteFilter.instance;
  final rating4 = RatingFilter(4);
  final video = MimeFilter.video;

  group('automatic split', () {
    test('one album becomes one source', () {
      final split = splitVisibleRangePin({albumA});
      expect(split.sources, [
        {albumA},
      ]);
      expect(split.restrictions, isEmpty);
      expect(split.supplements, isEmpty);
    });

    test('two albums stay one conjunctive source, not a union', () {
      final split = splitVisibleRangePin({albumA, albumB});
      expect(split.sources, [
        {albumA, albumB},
      ]);
    });

    test('a source-only union becomes one source per member', () {
      final split = splitVisibleRangePin({
        SetOrFilter({albumA, albumB}),
      });
      expect(split.sources, [
        {albumA},
        {albumB},
      ]);
    });

    test('a source plus narrowing filters becomes one source and restrictions', () {
      final split = splitVisibleRangePin({albumA, favourite, rating4});
      expect(split.sources, [
        {albumA},
      ]);
      expect(split.restrictions, [favourite, rating4]);
    });

    test('a reversed filter never becomes a source', () {
      final reversed = PathFilter('/a', reversed: true);
      final split = splitVisibleRangePin({reversed});
      expect(split.sources, isEmpty);
      expect(split.restrictions, [reversed]);
    });

    test('a mixed union stays one restriction', () {
      final union = SetOrFilter({albumA, video});
      final split = splitVisibleRangePin({union});
      // video is not a source scope, so the union is not a source: as a
      // restriction it still preserves the original union exactly.
      expect(split.sources, isEmpty);
      expect(split.restrictions, [union]);
    });

    test('nothing splits into nothing', () {
      expect(splitVisibleRangePin(const {}).isEmpty, isTrue);
    });
  });

  group('forced role', () {
    test('forcing the source role keeps the whole set conjunctive', () {
      final split = splitVisibleRangePin({albumA, favourite}, forcedRole: VisibleRangeRuleKind.source);
      expect(split.sources, [
        {albumA, favourite},
      ]);
      expect(split.restrictions, isEmpty);
    });

    test('forcing restrictions puts every filter in its own rule', () {
      final split = splitVisibleRangePin({albumA, favourite}, forcedRole: VisibleRangeRuleKind.restriction);
      expect(split.sources, isEmpty);
      expect(split.restrictions, [albumA, favourite]);
    });

    test('forcing supplements puts every filter in its own OR rule', () {
      final split = splitVisibleRangePin({albumA, favourite}, forcedRole: VisibleRangeRuleKind.supplement);
      expect(split.sources, isEmpty);
      expect(split.supplements, [albumA, favourite]);
    });
  });

  group('source scope', () {
    test('albums and paths are sources, other filters are not', () {
      expect(isVisibleRangeSourceScope(albumA), isTrue);
      expect(isVisibleRangeSourceScope(favourite), isFalse);
      expect(isVisibleRangeSourceScope(video), isFalse);
    });

    test('a union of sources is a source, a mixed union is not', () {
      expect(isVisibleRangeSourceScope(SetOrFilter({albumA, albumB})), isTrue);
      expect(isVisibleRangeSourceScope(SetOrFilter({albumA, favourite})), isFalse);
      expect(isVisibleRangeSourceScope(SetOrFilter(const {})), isFalse);
    });
  });
}
