import 'dart:async';

import 'package:aves/features/wallpaper_auto_advance/model/wallpaper_advance_interval.dart';
import 'package:aves/features/wallpaper_auto_advance/view/widgets/wallpaper_interval_add_sheet.dart';
import 'package:aves/l10n/l10n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// The editor is four digits-only boxes (days, hours, minutes, seconds) plus a
/// confirm row; these tests pin the prefill, the bounds and the shell choice.
void main() {
  late WallpaperAdvanceInterval? result;

  setUp(() => result = null);

  Widget wrap(WallpaperAdvanceInterval current) => MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => unawaited(showWallpaperIntervalAddSheet(context, current: current).then((value) => result = value)),
              child: const Text('open'),
            ),
          ),
        ),
      );

  Future<void> open(WidgetTester tester, WallpaperAdvanceInterval current) async {
    await tester.pumpWidget(wrap(current));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Finder field(int index) => find.byType(TextField).at(index);

  String textOf(WidgetTester tester, int index) => tester.widget<TextField>(field(index)).controller!.text;

  testWidgets('opening on Off seeds ten minutes and confirms them', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await open(tester, WallpaperAdvanceInterval.off);

    // Wide layout on a phone: a bottom sheet, not a dialog.
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(4));
    expect(textOf(tester, 0), isEmpty);
    expect(textOf(tester, 1), isEmpty);
    expect(textOf(tester, 2), '10');
    expect(textOf(tester, 3), isEmpty);
    expect(find.text('Every 10 minutes'), findsOneWidget);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(result, const WallpaperAdvanceInterval(600));
  });

  testWidgets('an existing interval is decomposed into the boxes', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await open(tester, const WallpaperAdvanceInterval(90));

    expect(textOf(tester, 2), '1');
    expect(textOf(tester, 3), '30');

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(result, const WallpaperAdvanceInterval(90));
  });

  testWidgets('all-zero boxes are invalid, so OK is disabled', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await open(tester, WallpaperAdvanceInterval.off);
    await tester.enterText(field(2), '');
    await tester.pump();

    expect(find.text('Enter a value between 3 seconds and 30 days.'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'OK')).onPressed, isNull);

    await tester.enterText(field(3), '3');
    await tester.pump();

    expect(find.text('Every 3 seconds'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(result, const WallpaperAdvanceInterval(3));
  });

  testWidgets('a box rejects a value above one thousand', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await open(tester, WallpaperAdvanceInterval.off);

    await tester.enterText(field(0), '2000');
    await tester.pump();
    expect(textOf(tester, 0), isEmpty, reason: 'the rejected edit leaves the box empty');

    await tester.enterText(field(0), '1000');
    await tester.pump();
    expect(textOf(tester, 0), '1000');
  });

  testWidgets('a total beyond thirty days keeps OK disabled', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await open(tester, WallpaperAdvanceInterval.off);
    await tester.enterText(field(0), '1000');
    await tester.pump();

    expect(find.text('Enter a value between 3 seconds and 30 days.'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'OK')).onPressed, isNull);
  });

  testWidgets('a wide screen opens the same form as a dialog', (tester) async {
    tester.view.physicalSize = const Size(900, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await open(tester, WallpaperAdvanceInterval.off);

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(TextField), findsNWidgets(4));
  });
}
