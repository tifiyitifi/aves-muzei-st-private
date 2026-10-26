import 'package:aves/features/visible_range/data/default_presets.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/filters/mime.dart';
import 'package:aves/model/filters/path.dart';
import 'package:aves/services/common/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// The bundled preset document: tolerant parsing, section kinds, device paths
/// and a sanity check on the shipped list.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    getIt.registerLazySingleton<p.Context>(() => p.Context(style: p.Style.posix));
  });

  tearDownAll(getIt.reset);

  test('parses valid presets and skips malformed entries', () {
    final definitions = parseVisibleRangePresetBundle('''
      {
        "version": 2,
        "presets": [
          {"id": "a", "kind": "base", "nameKey": "visibleRangePresetImage", "filters": [{"type": "mime", "mime": "image/*"}]},
          {"id": "", "nameKey": "x", "filters": []},
          {"nameKey": "x", "filters": []},
          {"id": "b", "kind": "restriction", "nameKey": "x", "filters": [{"type": "unknown-type"}]},
          {"id": "c", "kind": "nonsense", "nameKey": "x", "filters": [{"type": "favourite"}]}
        ]
      }
    ''');

    expect(definitions.map((d) => d.id), ['a', 'c']);
    expect(definitions.first.filters, {MimeFilter.image});
    expect(definitions.first.kind, VisibleRangePresetKind.base);
    // An unknown kind falls back to base rather than hiding the candidate.
    expect(definitions.last.kind, VisibleRangePresetKind.base);
  });

  test('a document without a preset list yields nothing', () {
    expect(parseVisibleRangePresetBundle('{"version": 2}'), isEmpty);
    expect(parseVisibleRangePresetBundle('not json at all'), isEmpty);
  });

  test('a standard directory is resolved instead of hardcoded', () {
    final definitions = parseVisibleRangePresetBundle(
      '''
      {
        "presets": [
          {"id": "camera", "kind": "base", "nameKey": "visibleRangePresetCamera", "filters": [{"type": "path", "standard": "dcim"}]}
        ]
      }
      ''',
      standardPath: (standard) => '/storage/emulated/0/${standard.toUpperCase()}',
    );
    expect(definitions.single.filters.single, PathFilter('/storage/emulated/0/DCIM'));
  });

  test('an unresolvable standard directory skips the candidate', () {
    final definitions = parseVisibleRangePresetBundle(
      '''
      {
        "presets": [
          {"id": "camera", "nameKey": "visibleRangePresetCamera", "filters": [{"type": "path", "standard": "dcim"}]},
          {"id": "image", "nameKey": "visibleRangePresetImage", "filters": [{"type": "mime", "mime": "image/*"}]}
        ]
      }
      ''',
      standardPath: (_) => null,
    );
    // A preset without a usable filter would match everything; it is dropped.
    expect(definitions.map((d) => d.id), ['image']);
  });

  test('the shipped bundle parses with unique ids, sections and decodable filters', () async {
    final definitions = await loadVisibleRangePresetDefinitions(standardPath: (standard) => '/standard/$standard');
    expect(definitions, isNotEmpty);
    expect(definitions.map((d) => d.id).toSet(), hasLength(definitions.length));
    expect(definitions.map((d) => d.kind).toSet(), VisibleRangePresetKind.values.toSet());
    for (final definition in definitions) {
      expect(definition.nameKey, startsWith('visibleRangePreset'));
      expect(definition.filters, isNotEmpty, reason: definition.id);
      for (final filter in definition.filters) {
        expect(filter, isA<CollectionFilter>());
      }
    }
  });
}
