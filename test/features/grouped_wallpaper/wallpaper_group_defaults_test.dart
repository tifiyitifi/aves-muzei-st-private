import 'package:aves/features/grouped_wallpaper/data/default_groups.dart';
import 'package:aves/model/filters/container/set_or.dart';
import 'package:aves/model/filters/path.dart';
import 'package:aves/services/common/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// The bundled group document: tolerant parsing, device paths and the
/// fail-closed rule.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    getIt.registerLazySingleton<p.Context>(() => p.Context(style: p.Style.posix));
  });

  tearDownAll(getIt.reset);

  test('parses the group list and skips malformed entries', () {
    final definitions = parseWallpaperGroupBundle(
      '''
      {
        "version": 1,
        "groups": [
          {"id": "a", "nameKey": "wallpaperGroupDefaultAll", "filters": []},
          {"id": "", "nameKey": "x", "filters": []},
          {"nameKey": "x", "filters": []},
          {"id": "b", "nameKey": "wallpaperGroupDefaultDcim", "enabled": false, "filters": [{"type": "path", "standard": "dcim"}]}
        ]
      }
      ''',
      standardPath: (standard) => '/standard/$standard',
    );

    expect(definitions.map((definition) => definition.id), ['a', 'b']);
    expect(definitions.first.filters, isEmpty);
    expect(definitions.last.enabled, isFalse);
    expect(definitions.last.filters.single, PathFilter('/standard/dcim'));
  });

  test('a group whose folder cannot be resolved is closed, not unrestricted', () {
    final definitions = parseWallpaperGroupBundle(
      '''
      {
        "groups": [
          {"id": "dcim", "nameKey": "wallpaperGroupDefaultDcim", "filters": [{"type": "path", "standard": "dcim"}]}
        ]
      }
      ''',
      standardPath: (_) => null,
    );

    final filters = definitions.single.filters;
    // The group still exists, so the user sees why its folder is missing...
    expect(filters, isNotEmpty);
    // ...but it matches nothing: a privacy range fails closed.
    expect(filters.single, isA<SetOrFilter>());
    expect((filters.single as SetOrFilter).innerFilters, isEmpty);
    expect(filters.single, wallpaperDenyAllFilter());
  });

  test('a closed group is never reported as unrestricted', () {
    final definition = parseWallpaperGroupBundle(
      '''
      {"groups": [{"id": "pictures", "nameKey": "x", "filters": [{"type": "path", "standard": "pictures"}]}]}
      ''',
      standardPath: (_) => null,
    ).single;

    expect(definition.filters, isNotEmpty);
  });

  test('the shipped bundle declares pictures, dcim and all in that order', () async {
    final definitions = await loadWallpaperGroupDefinitions(standardPath: (standard) => '/standard/$standard');

    expect(definitions.map((definition) => definition.id), [
      'wallpaper.group.pictures',
      'wallpaper.group.dcim',
      'wallpaper.group.all',
    ]);
    expect(definitions.map((definition) => definition.nameKey), [
      'wallpaperGroupDefaultPictures',
      'wallpaperGroupDefaultDcim',
      'wallpaperGroupDefaultAll',
    ]);
    expect(definitions.map((definition) => definition.id).toSet(), hasLength(definitions.length));
    // Group 1 (Pictures) is the only current one; every default joins the rotation.
    expect(definitions.map((definition) => definition.current), [true, false, false]);
    expect(definitions.every((definition) => definition.enabled), isTrue);
    expect(definitions.last.filters, isEmpty);
    expect(definitions.take(2).every((definition) => definition.filters.single is PathFilter), isTrue);
  });
}
