import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/visible_range/data/default_presets.dart';
import 'package:aves/features/visible_range/db/visible_range_store.dart';
import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/features/visible_range/model/visible_range_usage.dart';
import 'package:aves/features/visible_range/services/visible_range_controller.dart';
import 'package:aves/features/visible_range/view/visible_range_pin_sheet.dart';
import 'package:aves/features/visible_range/view/widgets/visible_range_target_grid.dart';
import 'package:aves/l10n/l10n.dart';
import 'package:aves/model/filters/mime.dart';
import 'package:aves/services/common/services.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../../helpers/sqlite3_loader.dart';

/// The save sheet's targets, section labels and advanced options. A real
/// injected controller gives the sheet the groups a device would show, so the
/// default selection and the live write summary are observable here.
void main() {
  setUpAll(() {
    ensureSqlite3Loaded();
    getIt.registerLazySingleton<p.Context>(() => p.Context(style: p.Style.posix));
  });

  tearDownAll(getIt.reset);

  late AppDatabase db;
  late VisibleRangeController controller;

  // A distinct key makes a reopen a new sheet state, not a rebuild of the old
  // one: Flutter would otherwise reuse the State because the widget type matches.
  var generation = 0;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    controller = VisibleRangeController(
      injectedDatabase: db,
      presetLoader: () async => [
        VisibleRangePresetDefinition(id: 'builtin.image', nameKey: 'visibleRangePresetImage', filters: {MimeFilter.image}),
      ],
    );
    await controller.init();
  });

  tearDown(() => db.close());

  Future<void> pumpSheet(WidgetTester tester, {bool withTargets = true}) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: VisibleRangePinSheet(
            key: ValueKey(generation++),
            controller: withTargets ? controller : null,
            filters: const {},
            initialName: 'Pinned',
            initialDescription: 'now',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapLabel(WidgetTester tester, String label) async {
    final finder = find.text(label);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> expandOptions(WidgetTester tester) async {
    await tapLabel(tester, 'Injection options');
  }

  Future<void> tapTarget(WidgetTester tester, String id) async {
    final finder = find.byKey(ValueKey('pin-target-$id'));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('the sheet opens with nothing selected', (tester) async {
    await pumpSheet(tester);

    // The groups are there, so a disabled save is not just an empty sheet.
    expect(find.byType(VisibleRangeTargetGrid), findsNWidgets(2));
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    expect(find.text('Choose at least one target.'), findsOneWidget);
  });

  testWidgets('the gallery section is named apart from the wallpaper one', (tester) async {
    await pumpSheet(tester);

    expect(find.text('Normal groups'), findsOneWidget);
    expect(find.text('Outside groups'), findsOneWidget);
    expect(find.text('Groups'), findsNothing);
  });

  testWidgets('ticking a group adds it to the expected write locations', (tester) async {
    await pumpSheet(tester);
    final groupId = controller.galleryGroups.firstWhere((group) => group.id != VisibleRange.galleryRangeId).id;
    final expected = find.byKey(const Key('visibleRangeExpectedWrites'));
    expect(tester.widget<Text>(expected).data, 'Nothing will be written.');

    await tapTarget(tester, groupId);
    expect(tester.widget<Text>(expected).data, 'Group 1 · Images');

    await tapTarget(tester, groupId);
    expect(tester.widget<Text>(expected).data, 'Nothing will be written.');
  });

  testWidgets('ticking a rule reaches the expected locations without closing the sheet', (tester) async {
    final group = controller.galleryGroupById(visibleRangeBuiltinGroupId('builtin.image'))!;
    final rule = group.rulesOf(VisibleRangeRuleKind.source).single;
    await VisibleRangeStore(db).saveUsage(VisibleRangeRuleUsage.forRule(ruleId: rule.id, rangeId: group.id, kind: rule.kind, usedAt: 1));

    await pumpSheet(tester);
    await expandOptions(tester);
    expect(find.byType(CheckboxListTile), findsOneWidget);

    final row = find.byType(CheckboxListTile);
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(tester.widget<Text>(find.byKey(const Key('visibleRangeExpectedWrites'))).data, 'Group 1 · Images · Base range');
  });

  testWidgets('the role starts from the automatic split on every open', (tester) async {
    await pumpSheet(tester, withTargets: false);
    await expandOptions(tester);
    expect(find.text('Split automatically'), findsOneWidget);
    expect(find.text('Custom'), findsOneWidget);

    // A custom role affects this save only; reopening the sheet resets it.
    await tapLabel(tester, 'Custom');
    await tapLabel(tester, 'Restriction');
    expect(find.text('Restriction'), findsOneWidget);

    await pumpSheet(tester, withTargets: false);
    await expandOptions(tester);
    expect(find.text('Split automatically'), findsOneWidget);
    expect(find.text('Custom'), findsOneWidget);
    expect(find.text('Restriction'), findsNothing);
  });

  testWidgets('the custom role button opens the role menu on every tap', (tester) async {
    await pumpSheet(tester, withTargets: false);
    await expandOptions(tester);
    await tapLabel(tester, 'Custom');
    await tapLabel(tester, 'Base range');

    // The button now reads as the chosen role, but a second tap asks again.
    await tapLabel(tester, 'Base range');
    expect(find.text('Restriction'), findsOneWidget);
    expect(find.text('Supplement'), findsOneWidget);
  });

  testWidgets('the existing conditions choice is two named buttons, not a switch', (tester) async {
    await pumpSheet(tester, withTargets: false);
    await expandOptions(tester);
    expect(find.text('Append'), findsOneWidget);
    expect(find.text('Replace'), findsOneWidget);
    // Only the remember option still uses a switch.
    expect(find.byType(Switch), findsOneWidget);
  });

  testWidgets('the remember option names what it stores', (tester) async {
    await pumpSheet(tester, withTargets: false);
    await expandOptions(tester);
    expect(find.text('Remember the injection option'), findsOneWidget);
    expect(find.textContaining('not remembered'), findsOneWidget);
  });

  testWidgets('the expected write locations stay outside the collapsible section', (tester) async {
    await pumpSheet(tester);
    expect(find.text('Expected write locations'), findsOneWidget);
    expect(find.text('Nothing will be written.'), findsOneWidget);
    expect(find.text('No rule has opened a media set yet.'), findsNothing);
  });
}
