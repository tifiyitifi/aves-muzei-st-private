import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_command.dart';
import 'package:flutter_test/flutter_test.dart';

/// The names the Kotlin notification and the Dart engine share.
void main() {
  test('parses every command by its exact name', () {
    for (final command in GroupedWallpaperCommand.values) {
      expect(GroupedWallpaperCommand.tryParse(command.name), command);
    }
  });

  test('ignores an unknown or missing command', () {
    expect(GroupedWallpaperCommand.tryParse('deleteEverything'), isNull);
    expect(GroupedWallpaperCommand.tryParse(null), isNull);
    expect(GroupedWallpaperCommand.tryParse(3), isNull);
  });
}
