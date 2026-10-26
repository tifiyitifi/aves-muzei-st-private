import 'package:aves/features/visible_range/data/default_presets.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/filters/mime.dart';
import 'package:flutter_test/flutter_test.dart';

/// The bundled preset document: tolerant parsing, and a sanity check on the
/// shipped list.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('parses valid presets and skips malformed entries', () {
    final definitions = parseVisibleRangePresetBundle('''
      {
        "version": 1,
        "presets": [
          {"id": "a", "nameKey": "visibleRangePresetImage", "filters": [{"type": "mime", "mime": "image/*"}]},
          {"id": "", "nameKey": "x", "filters": []},
          {"nameKey": "x", "filters": []},
          {"id": "b", "nameKey": "x", "filters": [{"type": "unknown-type"}]}
        ]
      }
    ''');

    expect(definitions.map((d) => d.id), ['a', 'b']);
    expect(definitions.first.filters, {MimeFilter.image});
    expect(definitions.last.filters, isEmpty);
  });

  test('a document without a preset list yields nothing', () {
    expect(parseVisibleRangePresetBundle('{"version": 1}'), isEmpty);
    expect(parseVisibleRangePresetBundle('not json at all'), isEmpty);
  });

  test('the shipped bundle parses with unique ids and decodable filters', () async {
    final definitions = await loadVisibleRangePresetDefinitions();
    expect(definitions, isNotEmpty);
    expect(definitions.map((d) => d.id).toSet(), hasLength(definitions.length));
    for (final definition in definitions) {
      expect(definition.nameKey, startsWith('visibleRangePreset'));
      expect(definition.filters, isNotEmpty, reason: definition.id);
      for (final filter in definition.filters) {
        expect(filter, isA<CollectionFilter>());
      }
    }
  });
}
