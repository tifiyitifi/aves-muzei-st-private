import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/wallpaper_auto_advance/data/default_intervals.dart';
import 'package:aves/features/wallpaper_auto_advance/db/wallpaper_interval_options_store.dart';
import 'package:aves/features/wallpaper_auto_advance/model/wallpaper_advance_interval.dart';
import 'package:aves/features/wallpaper_auto_advance/model/wallpaper_interval_catalog.dart';
import 'package:aves/features/wallpaper_auto_advance/services/wallpaper_interval_options_controller.dart';
import 'package:aves/features/wallpaper_auto_advance/view/widgets/wallpaper_interval_option_list.dart';
import 'package:aves/l10n/l10n.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../../helpers/sqlite3_loader.dart';

/// Every option but Off can be deleted, built-ins included; Off is the only
/// pinned one because it is the off switch.
void main() {
  setUpAll(ensureSqlite3Loaded);

  const bundled = WallpaperIntervalDefaults(
    version: 1,
    defaultInterval: WallpaperAdvanceInterval.off,
    intervals: [
      WallpaperAdvanceInterval.off,
      WallpaperAdvanceInterval(900),
      WallpaperAdvanceInterval(3600),
    ],
  );

  late AppDatabase db;
  late WallpaperIntervalOptionsController controller;
  late WallpaperAdvanceInterval selected;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final store = WallpaperIntervalOptionsStore(db, bundledLoader: () async => bundled);
    await store.write(
      WallpaperIntervalCatalog(
        defaultInterval: bundled.defaultInterval,
        shippedDefaults: bundled.intervals,
        defaults: bundled.intervals,
        customs: const [WallpaperAdvanceInterval(7200)],
      ),
    );
    controller = WallpaperIntervalOptionsController(
      injectedDatabase: db,
      bundledLoader: () async => bundled,
      selectionReset: ({required removed, required all, required fallback}) async {},
    );
    selected = WallpaperAdvanceInterval.off;
  });

  tearDown(() async {
    controller.dispose();
    await db.close();
  });

  Widget wrap() => MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: WallpaperIntervalOptionList(
              selected: selected,
              onSelected: (value) => selected = value,
              controller: controller,
            ),
          ),
        ),
      );

  testWidgets('long-pressing a built-in starts selecting it', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Every 15 minutes'));
    await tester.pumpAndSettle();

    expect(find.text('1 selected'), findsOneWidget);
    // Every deletable option gets a checkbox; Off stays locked.
    expect(find.byType(Checkbox), findsNWidgets(3));
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
  });

  testWidgets('Off cannot be selected for deletion', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Off'));
    await tester.pumpAndSettle();

    expect(find.text('Off cannot be deleted. It always stays in the list so auto-advance can be turned off.'), findsOneWidget);
    expect(find.byType(Checkbox), findsNothing);
    expect(find.text('1 selected'), findsNothing);
  });

  testWidgets('a value that is only the current selection is not deletable', (tester) async {
    selected = const WallpaperAdvanceInterval(1234);
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Every 1234 seconds'));
    await tester.pumpAndSettle();

    expect(find.text('1 selected'), findsNothing);
    expect(find.byType(Checkbox), findsNothing);
    // Tagged so it cannot be mistaken for a built-in.
    expect(find.text('Current value'), findsOneWidget);
  });

  testWidgets('a built-in and a custom option can be selected together', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Every hour'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Every 2 hours'));
    await tester.pumpAndSettle();

    expect(find.text('2 selected'), findsOneWidget);
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Delete')).onPressed, isNotNull);
  });
}
