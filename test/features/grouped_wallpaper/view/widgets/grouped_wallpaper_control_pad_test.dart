import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_control_pad_layout.dart';
import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_pad_config.dart';
import 'package:aves/features/grouped_wallpaper/view/widgets/grouped_wallpaper_control_pad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The view page's floating pad: it must stay inside the screen, remember only
/// the place a drag actually reached, and keep every cell reachable.
void main() {
  const viewport = Size(400, 800);
  const square = GroupedWallpaperPadShape(3, 3);
  const squareExtent = Size(16 + 3 * groupedWallpaperControlPadCell, 3 * groupedWallpaperControlPadCell);

  final taps = <String>[];
  final moved = <GroupedWallpaperControlPadPosition>[];

  setUp(() {
    taps.clear();
    moved.clear();
  });

  Widget cell(String key) => SizedBox(
    key: ValueKey(key),
    width: groupedWallpaperControlPadCell,
    height: groupedWallpaperControlPadCell,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => taps.add(key),
      child: const ColoredBox(color: Color(0xFF333333)),
    ),
  );

  List<Widget?> cells({int extra = 0}) => [for (var i = 0; i < 9 - extra; i++) cell('c$i'), for (var i = 0; i < extra; i++) null];

  GroupedWallpaperControlPadPosition centered({Size size = viewport}) => groupedWallpaperControlPadCenteredDefault(
    viewportSize: size,
    safeInsets: EdgeInsets.zero,
    extent: squareExtent,
  );

  /// Pumps the pad on a surface exactly [size] big, so a drag can reach every
  /// corner instead of running off the test window.
  Future<void> pumpPad(
    WidgetTester tester, {
    required ValueNotifier<GroupedWallpaperControlPadPosition> position,
    Size size = viewport,
    bool visible = true,
    GroupedWallpaperPadShape shape = square,
    List<Widget?>? children,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              GroupedWallpaperControlPad(
                position: position,
                viewportSize: size,
                safeInsets: EdgeInsets.zero,
                onMoved: moved.add,
                visible: visible,
                shape: shape,
                cells: children ?? cells(),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('starts with its top-left at the screen center', (tester) async {
    await pumpPad(tester, position: ValueNotifier(centered()));

    final topLeft = tester.getTopLeft(find.byType(GroupedWallpaperControlPad));
    expect(topLeft.dx, closeTo(viewport.width / 2, .001));
    expect(topLeft.dy, closeTo(viewport.height / 2, .001));
    expect(tester.getSize(find.byType(GroupedWallpaperControlPad)), squareExtent);
  });

  testWidgets('a drag past the edge is clamped and remembered once', (tester) async {
    final position = ValueNotifier(centered());
    await pumpPad(tester, position: position);

    await tester.drag(find.byType(GroupedWallpaperControlPad), const Offset(1000, 1000));
    await tester.pumpAndSettle();

    expect(position.value, const GroupedWallpaperControlPadPosition(1, 1));
    expect(moved, [const GroupedWallpaperControlPadPosition(1, 1)]);
    expect(
      tester.getTopLeft(find.byType(GroupedWallpaperControlPad)),
      Offset(
        viewport.width - groupedWallpaperControlPadMargin - squareExtent.width,
        viewport.height - groupedWallpaperControlPadMargin - squareExtent.height,
      ),
    );

    // The accumulator keeps the drag alive from the pinned edge.
    await tester.drag(find.byType(GroupedWallpaperControlPad), const Offset(-1000, -1000));
    await tester.pumpAndSettle();
    expect(position.value, const GroupedWallpaperControlPadPosition(0, 0));
    expect(moved, hasLength(2));
  });

  testWidgets('a tap on a cell reaches it without saving a place', (tester) async {
    await pumpPad(tester, position: ValueNotifier(centered()));

    await tester.tap(find.byKey(const ValueKey('c0')));
    await tester.tap(find.byKey(const ValueKey('c6')));

    expect(taps, ['c0', 'c6']);
    expect(moved, isEmpty);
  });

  testWidgets('an empty cell still drags the pad but is not a button', (tester) async {
    final position = ValueNotifier(centered());
    // The default layout leaves slot 5, then 7 and 8 empty.
    await pumpPad(
      tester,
      position: position,
      children: [cell('c0'), cell('c1'), cell('c2'), cell('c3'), cell('c4'), null, cell('c6'), null, null],
    );

    // Slot 5 and 7..8 are empty in the default layout; slot 5 is the middle
    // row's last cell, between the two group steps and the delete button.
    final origin = tester.getTopLeft(find.byType(GroupedWallpaperControlPad));
    await tester.tapAt(origin + const Offset(groupedWallpaperControlPadHandleWidth + 2 * groupedWallpaperControlPadCell + 24, groupedWallpaperControlPadCell + 24));
    expect(taps, isEmpty);

    await tester.dragFrom(origin + const Offset(72, 72), const Offset(-40, -40));
    await tester.pumpAndSettle();
    expect(moved, hasLength(1));
  });

  testWidgets('a hidden pad ignores taps', (tester) async {
    await pumpPad(tester, position: ValueNotifier(centered()), visible: false);

    await tester.tap(find.byKey(const ValueKey('c6')), warnIfMissed: false);

    expect(taps, isEmpty);
  });

  testWidgets('an adaptive shape uses a smaller box', (tester) async {
    const shape = GroupedWallpaperPadShape(2, 1);
    final position = ValueNotifier(
      groupedWallpaperControlPadCenteredDefault(
        viewportSize: viewport,
        safeInsets: EdgeInsets.zero,
        extent: groupedWallpaperControlPadExtentFor(columns: 2, rows: 1),
      ),
    );
    await pumpPad(tester, position: position, shape: shape, children: [cell('a'), cell('b')]);

    expect(
      tester.getSize(find.byType(GroupedWallpaperControlPad)),
      groupedWallpaperControlPadExtentFor(columns: 2, rows: 1),
    );
  });

  testWidgets('a smaller screen re-clamps the same fractional place', (tester) async {
    const small = Size(300, 200);
    final position = ValueNotifier(
      groupedWallpaperControlPadCenteredDefault(viewportSize: small, safeInsets: EdgeInsets.zero, extent: squareExtent),
    );
    await pumpPad(tester, position: position, size: small);

    final topLeft = tester.getTopLeft(find.byType(GroupedWallpaperControlPad));
    expect(topLeft.dx, lessThanOrEqualTo(small.width - groupedWallpaperControlPadMargin - squareExtent.width + .001));
    expect(topLeft.dy, lessThanOrEqualTo(small.height - groupedWallpaperControlPadMargin - squareExtent.height + .001));
  });
}
