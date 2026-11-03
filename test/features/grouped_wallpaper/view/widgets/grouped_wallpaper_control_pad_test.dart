import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_control_pad_layout.dart';
import 'package:aves/features/grouped_wallpaper/view/widgets/grouped_wallpaper_control_pad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The view page's floating pad: it must stay inside the screen, remember only
/// the place a drag actually reached, and leave the photo's own tap reachable.
void main() {
  const viewport = Size(400, 800);

  final taps = <String>[];
  final moved = <GroupedWallpaperControlPadPosition>[];

  setUp(() {
    taps.clear();
    moved.clear();
  });

  Widget row(List<String> keys) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final key in keys)
        SizedBox(
          key: ValueKey(key),
          width: groupedWallpaperControlPadCell,
          height: groupedWallpaperControlPadCell,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => taps.add(key),
            child: const ColoredBox(color: Color(0xFF333333)),
          ),
        ),
    ],
  );

  /// Pumps the pad on a surface exactly [size] big, so a drag can reach every
  /// corner instead of running off the test window.
  Future<void> pumpPad(
    WidgetTester tester, {
    required ValueNotifier<GroupedWallpaperControlPadPosition> position,
    Size size = viewport,
    bool visible = true,
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
                topRow: row(['t0', 't1', 't2']),
                middleRow: row(['m0', 'm1']),
                bottomRow: row(['b0']),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('starts at the thumb anchor inside the safe area', (tester) async {
    await pumpPad(tester, position: ValueNotifier(GroupedWallpaperControlPadPosition.defaultPosition));

    final freeHeight = viewport.height - 2 * groupedWallpaperControlPadMargin - groupedWallpaperControlPadExtent;
    final topLeft = tester.getTopLeft(find.byType(GroupedWallpaperControlPad));
    expect(topLeft.dx, groupedWallpaperControlPadMargin);
    expect(topLeft.dy, closeTo(groupedWallpaperControlPadMargin + GroupedWallpaperControlPadPosition.defaultPosition.y * freeHeight, .001));
  });

  testWidgets('a drag past the edge is clamped and remembered once', (tester) async {
    final position = ValueNotifier(GroupedWallpaperControlPadPosition.defaultPosition);
    await pumpPad(tester, position: position);

    await tester.drag(find.byType(GroupedWallpaperControlPad), const Offset(1000, 1000));
    await tester.pumpAndSettle();

    expect(position.value, const GroupedWallpaperControlPadPosition(1, 1));
    expect(moved, [const GroupedWallpaperControlPadPosition(1, 1)]);
    expect(
      tester.getTopLeft(find.byType(GroupedWallpaperControlPad)),
      Offset(
        viewport.width - groupedWallpaperControlPadMargin - groupedWallpaperControlPadExtent,
        viewport.height - groupedWallpaperControlPadMargin - groupedWallpaperControlPadExtent,
      ),
    );

    // The accumulator keeps the drag alive from the pinned edge.
    await tester.drag(find.byType(GroupedWallpaperControlPad), const Offset(-1000, -1000));
    await tester.pumpAndSettle();
    expect(position.value, const GroupedWallpaperControlPadPosition(0, 0));
    expect(moved, hasLength(2));
  });

  testWidgets('a tap on a cell reaches it without saving a place', (tester) async {
    await pumpPad(tester, position: ValueNotifier(GroupedWallpaperControlPadPosition.defaultPosition));

    await tester.tap(find.byKey(const ValueKey('m0')));
    await tester.tap(find.byKey(const ValueKey('b0')));

    expect(taps, ['m0', 'b0']);
    expect(moved, isEmpty);
  });

  testWidgets('a hidden pad ignores taps', (tester) async {
    await pumpPad(
      tester,
      position: ValueNotifier(GroupedWallpaperControlPadPosition.defaultPosition),
      visible: false,
    );

    await tester.tap(find.byKey(const ValueKey('b0')), warnIfMissed: false);

    expect(taps, isEmpty);
  });

  testWidgets('a smaller screen re-clamps the same fractional place', (tester) async {
    const small = Size(300, 200);
    await pumpPad(
      tester,
      position: ValueNotifier(const GroupedWallpaperControlPadPosition(1, 1)),
      size: small,
    );

    expect(
      tester.getTopLeft(find.byType(GroupedWallpaperControlPad)),
      Offset(
        small.width - groupedWallpaperControlPadMargin - groupedWallpaperControlPadExtent,
        small.height - groupedWallpaperControlPadMargin - groupedWallpaperControlPadExtent,
      ),
    );
  });
}
