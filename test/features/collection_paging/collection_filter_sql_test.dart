import 'package:aves/features/collection_paging/query/collection_window_predicate.dart';
import 'package:aves/model/filters/missing.dart';
import 'package:aves/model/filters/path.dart';
import 'package:aves/model/filters/type.dart';
import 'package:aves/model/metadata/catalog.dart';
import 'package:aves/services/common/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// The filter→SQL compiler: fragment shape and the `flags` bit layout it shares
/// with `CatalogMetadata`.
void main() {
  setUpAll(() {
    // `PathFilter` normalises through `pContext`.
    getIt.registerLazySingleton<p.Context>(() => p.Context(style: p.Style.posix));
  });

  tearDownAll(getIt.reset);

  group('metadata flag masks', () {
    // The bit values live in `CatalogMetadata`; the compiler keeps its own
    // copies so it can test a flag without loading a row. Deriving them from the
    // production serializer here means a layout change fails in this test
    // instead of silently emptying a filter.
    int flagsOf({bool animated = false, bool geotiff = false, bool is360 = false, bool motionPhoto = false, bool hdr = false, bool slowMotion = false}) => CatalogMetadata(
          id: 0,
          isAnimated: animated,
          isGeotiff: geotiff,
          is360: is360,
          isMotionPhoto: motionPhoto,
          isHdr: hdr,
          isSlowMotion: slowMotion,
        ).toMap()['flags']! as int;

    int compiledMask(TypeFilter filter) {
      final sql = filterTestFragment(filter)!.sql;
      return int.parse(RegExp(r'& (\d+)\)').firstMatch(sql)!.group(1)!);
    }

    test('match CatalogMetadata.toMap', () {
      expect(compiledMask(TypeFilter.animated), flagsOf(animated: true));
      expect(compiledMask(TypeFilter.geotiff), flagsOf(geotiff: true));
      expect(compiledMask(TypeFilter.hdr), flagsOf(hdr: true));
      expect(compiledMask(TypeFilter.motionPhoto), flagsOf(motionPhoto: true));
      expect(compiledMask(TypeFilter.panorama), flagsOf(is360: true));
      expect(compiledMask(TypeFilter.slowMotion), flagsOf(slowMotion: true));
      expect(compiledMask(TypeFilter.sphericalVideo), flagsOf(is360: true));
    });
  });

  group('path', () {
    test('matches the root directory itself and its descendants', () {
      final fragment = filterTestFragment(PathFilter('/a/b'))!;
      // `PathFilter.path` is normalised with a trailing separator.
      expect(fragment.sql, '(e.directory = ? OR substr(e.directory, 1, ?) = ?)');
      expect(fragment.variables.map((v) => v.value), ['/a/b', 5, '/a/b/']);
      expect(fragment.requires, isEmpty);
    });

    test('reverses NULL-safely', () {
      final fragment = filterTestFragment(PathFilter('/a/b').reverse())!;
      expect(fragment.sql, startsWith('COALESCE(('));
      expect(fragment.sql, endsWith(') = 0'));
    });
  });

  group('type', () {
    test('flags, mime prefixes and raw mimes are distinguished', () {
      expect(filterTestFragment(TypeFilter.animated)!.sql, '(COALESCE(m.flags, 0) & 1) != 0');
      // Panorama is an image flagged 360.
      expect(filterTestFragment(TypeFilter.panorama)!.sql, contains("substr(COALESCE(m.mimeType, e.sourceMimeType), 1, 5) = 'image'"));
      // Spherical/slow-motion videos are videos with their flag.
      expect(filterTestFragment(TypeFilter.sphericalVideo)!.sql, contains("substr(COALESCE(m.mimeType, e.sourceMimeType), 1, 5) = 'video'"));
      expect(filterTestFragment(TypeFilter.raw)!.sql, startsWith('COALESCE(m.mimeType, e.sourceMimeType) IN ('));
    });

    test('an unknown item type keeps the legacy path', () {
      expect(filterTestFragment(TypeFilter.fromMap(const {'itemType': 'bogus'})), isNull);
    });
  });

  group('missing', () {
    test('date and title read the catalogued metadata', () {
      expect(filterTestFragment(MissingFilter.date)!.sql, 'COALESCE(m.dateMillis, 0) = 0');
      expect(filterTestFragment(MissingFilter.title)!.sql, "COALESCE(m.xmpTitle, '') = ''");
    });

    test('fine address needs both metadata and address', () {
      final fragment = filterTestFragment(MissingFilter.fineAddress)!;
      expect(fragment.requires, {WindowTable.metadata, WindowTable.address});
      expect(fragment.sql, contains('COALESCE(m.latitude, 0) != 0'));
      expect(fragment.sql, contains('LENGTH(COALESCE(a.countryName, \'\')) > 3'));
    });
  });
}
