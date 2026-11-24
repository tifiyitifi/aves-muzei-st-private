import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/app_database_provider.dart';
import 'package:aves/features/grouped_wallpaper/db/wallpaper_group_store.dart';
import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_artwork_open_target.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_group.dart';
import 'package:aves/features/grouped_wallpaper/services/wallpaper_group_controller.dart';
import 'package:aves/features/grouped_wallpaper/view/grouped_wallpaper_settings_page.dart';
import 'package:aves/features/wallpaper_auto_advance/model/wallpaper_advance_interval.dart';
import 'package:aves/l10n/l10n.dart';
import 'package:aves/services/common/services.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../../helpers/sqlite3_loader.dart';

void main() {
  setUpAll(() {
    ensureSqlite3Loaded();
    getIt.registerLazySingleton<p.Context>(() => p.Context(style: p.Style.posix));
  });

  tearDownAll(getIt.reset);

  late AppDatabase db;
  late WallpaperGroupStore store;
  late WallpaperGroupController controller;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = WallpaperGroupStore(db);
    await store.writeDefaultsVersion(WallpaperGroupController.defaultsVersion);
    await store.saveGroups([
      const WallpaperGroup(id: 'group-a', number: 1, name: 'Group A', current: true, createdAt: 1, updatedAt: 1),
    ]);
    controller = WallpaperGroupController(injectedDatabase: db, defaultLoader: () async => []);
    getIt.registerSingleton<AppDatabaseProvider>(AppDatabaseProvider(injected: db));
  });

  tearDown(() async {
    await getIt.unregister<AppDatabaseProvider>();
    controller.dispose();
    await db.close();
  });

  Widget wrap(GroupedWallpaperSettingsPage page) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: page,
  );

  testWidgets('the settings page groups the low-frequency view settings', (tester) async {
    await tester.pumpWidget(wrap(GroupedWallpaperSettingsPage(groupId: 'group-a', controller: controller)));
    await tester.pumpAndSettle();

    expect(find.text('Grouped wallpaper settings'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Tap photo title'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Auto-advance'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Effects'), findsOneWidget);
    expect(find.widgetWithText(SwitchListTile, 'Show notification'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Gestures'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Wallpaper view buttons'), findsOneWidget);
  });

  testWidgets('the artwork title target can be changed from the settings page', (tester) async {
    await tester.pumpWidget(wrap(GroupedWallpaperSettingsPage(groupId: 'group-a', controller: controller)));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ListTile, 'Tap photo title'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open in album'));
    await tester.pumpAndSettle();

    expect(await store.readViewArtworkOpenTarget(), GroupedWallpaperArtworkOpenTarget.album);
    expect(find.widgetWithText(ListTile, 'Tap photo title'), findsOneWidget);
  });

  testWidgets('the auto-advance summary follows controller changes', (tester) async {
    await tester.pumpWidget(wrap(GroupedWallpaperSettingsPage(groupId: 'group-a', controller: controller)));
    await tester.pumpAndSettle();

    await controller.setAutoAdvance('group-a', interval: const WallpaperAdvanceInterval(Duration.secondsPerMinute));
    await tester.pump();

    final tile = tester.widget<ListTile>(find.widgetWithText(ListTile, 'Auto-advance'));
    expect((tile.subtitle as Text).data, 'Every minute');
  });

  testWidgets('group settings are disabled for an unresolved group', (tester) async {
    await tester.pumpWidget(wrap(GroupedWallpaperSettingsPage(groupId: 'missing', controller: controller)));
    await tester.pumpAndSettle();

    final autoAdvance = tester.widget<ListTile>(find.widgetWithText(ListTile, 'Auto-advance'));
    final effects = tester.widget<ListTile>(find.widgetWithText(ListTile, 'Effects'));
    final notification = tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'Show notification'));
    expect(autoAdvance.enabled, isFalse);
    expect(effects.enabled, isFalse);
    expect(notification.onChanged, isNotNull);
  });

  testWidgets('group settings are disabled without a playing group', (tester) async {
    await tester.pumpWidget(wrap(GroupedWallpaperSettingsPage(groupId: WallpaperGroup.none.id, controller: controller)));
    await tester.pumpAndSettle();

    final autoAdvance = tester.widget<ListTile>(find.widgetWithText(ListTile, 'Auto-advance'));
    final effects = tester.widget<ListTile>(find.widgetWithText(ListTile, 'Effects'));
    expect(autoAdvance.enabled, isFalse);
    expect(effects.enabled, isFalse);
  });
}
