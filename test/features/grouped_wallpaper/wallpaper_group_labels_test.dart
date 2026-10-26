import 'package:aves/features/grouped_wallpaper/model/wallpaper_group.dart';
import 'package:aves/features/grouped_wallpaper/view/wallpaper_group_labels.dart';
import 'package:aves/features/visible_range/view/visible_range_labels.dart';
import 'package:aves/l10n/l10n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Group names follow the app language while they are bundled, keep the user's
/// text once renamed, and fall back to the derived number when unnamed.
void main() {
  Future<({String bundled, String renamed, String unnamed, String baseName})> labels(WidgetTester tester) async {
    late ({String bundled, String renamed, String unnamed, String baseName}) result;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            result = (
              bundled: wallpaperGroupName(context, const WallpaperGroup(id: 'a', number: 1, name: '@wallpaperGroupDefaultDcim')),
              renamed: wallpaperGroupName(context, const WallpaperGroup(id: 'b', number: 2, name: 'Trips')),
              unnamed: wallpaperGroupName(context, const WallpaperGroup(id: 'c', number: 3)),
              // A group's base name is stored as the same ARB marker, so the
              // shared label helper has to resolve it too.
              baseName: visibleRangePresetLabel(context, 'wallpaperGroupDefaultPictures'),
            );
            return const SizedBox();
          },
        ),
      ),
    );
    return result;
  }

  testWidgets('a bundled group name follows the language', (tester) async {
    final result = await labels(tester);
    expect(result.bundled, 'DCIM');
  });

  testWidgets('a renamed group keeps the user text', (tester) async {
    expect((await labels(tester)).renamed, 'Trips');
  });

  testWidgets('an unnamed group falls back to its number', (tester) async {
    expect((await labels(tester)).unnamed, 'Group 3');
  });

  testWidgets('a wallpaper base name resolves to the same localized name', (tester) async {
    expect((await labels(tester)).baseName, 'Pictures');
  });
}
