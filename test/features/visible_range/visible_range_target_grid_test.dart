import 'package:aves/features/visible_range/model/visible_range_pin.dart';
import 'package:aves/features/visible_range/view/widgets/visible_range_target_grid.dart';
import 'package:aves/l10n/l10n.dart';
import 'package:aves/theme/icons.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// The responsive target grid of the pin sheet.
void main() {
  group('columnCountFor', () {
    test('adapts the column count to the width', () {
      expect(VisibleRangeTargetGrid.columnCountFor(320), 3);
      expect(VisibleRangeTargetGrid.columnCountFor(360), 3);
      expect(VisibleRangeTargetGrid.columnCountFor(480), 4);
      expect(VisibleRangeTargetGrid.columnCountFor(800), 7);
    });

    test('never drops below one column', () {
      expect(VisibleRangeTargetGrid.columnCountFor(0), 1);
      expect(VisibleRangeTargetGrid.columnCountFor(60), 1);
    });
  });

  VisibleRangePinTarget target(int number, {bool gallery = false, bool locked = false}) => VisibleRangePinTarget(
        rangeId: gallery ? 'gallery' : 'wallpaper.$number',
        number: number,
        name: gallery ? '' : 'Group $number',
        isGallery: gallery,
        locked: locked,
      );

  Widget wrap(Widget child) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: SizedBox(width: 320, child: child)),
      );

  testWidgets('renders the gallery and the groups and toggles unlocked targets', (tester) async {
    final targets = [
      target(0, gallery: true),
      for (var i = 1; i <= 6; i++) target(i),
    ];
    final toggled = <String>[];

    await tester.pumpWidget(
      wrap(
        VisibleRangeTargetGrid(
          targets: targets,
          selectedRangeIds: const {'gallery'},
          onToggle: (t) => toggled.add(t.rangeId),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Gallery'), findsOneWidget);
    for (var i = 1; i <= 6; i++) {
      expect(find.text('Group $i'), findsOneWidget);
    }

    await tester.tap(find.byKey(const ValueKey('pin-target-wallpaper.2')));
    expect(toggled, ['wallpaper.2']);
  });

  testWidgets('locked targets are not selectable', (tester) async {
    final toggled = <String>[];
    await tester.pumpWidget(
      wrap(
        VisibleRangeTargetGrid(
          targets: [target(0, gallery: true, locked: true)],
          selectedRangeIds: const {},
          onToggle: (t) => toggled.add(t.rangeId),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('pin-target-gallery')));
    expect(toggled, isEmpty);
    expect(find.byIcon(AIcons.locked), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsNothing);
  });
}
