import 'package:aves/model/selection.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/widgets/common/grid/selector.dart';
import 'package:aves/widgets/common/grid/sections/list_layout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../common.dart';

/// A layout that resolves each press to the row under it and records the
/// content-space position the gesture computed.
class _RowLayout extends SectionedListLayout<int> {
  static const _rowHeight = 40;

  final int rowCount;
  final int? forcedItem;

  Offset? lastPosition;

  new({
    required this.rowCount,
    this.forcedItem,
  }) : super(sections: const {}, showHeaders: true, spacing: 0, horizontalPadding: 0, sectionLayouts: const []);

  @override
  Rect? getTileRect(int item) => null;

  @override
  int? getItemAt(Offset position) {
    lastPosition = position;
    if (forcedItem != null) return forcedItem;
    final index = position.dy ~/ _rowHeight;
    return index >= 0 && index < rowCount ? index : null;
  }
}

void main() {
  setUpAll(() async {
    await setUpAllServices();
  });

  setUp(() async {
    await setUpServices();
  });

  Future<(_RowLayout, Selection<int>)> pumpSelector(
    WidgetTester tester, {
    required int rowCount,
    required double headerHeight,
    double appBarHeight = 0,
    int? forcedItem,
    bool Function(int item, Set<int> selected)? sameSelectionScope,
  }) async {
    final layout = _RowLayout(rowCount: rowCount, forcedItem: forcedItem);
    final selection = Selection<int>(toSelectableItems: null);
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    addTearDown(selection.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: MultiProvider(
          providers: [
            ChangeNotifierProvider<Selection<int>>.value(value: selection),
            Provider<SectionedListLayout<int>>.value(value: layout),
            Provider<MediaQueryData>.value(value: const MediaQueryData()),
          ],
          child: Scaffold(
            body: GridSelectionGestureDetector<int>(
              scrollableKey: GlobalKey(),
              items: [for (var i = 0; i < rowCount; i++) i],
              scrollController: scrollController,
              appBarHeightNotifier: ValueNotifier(appBarHeight),
              headerHeight: ValueNotifier(headerHeight),
              sameSelectionScope: sameSelectionScope,
              child: SingleChildScrollView(
                controller: scrollController,
                child: SizedBox(height: rowCount * 40, width: double.infinity),
              ),
            ),
          ),
        ),
      ),
    );
    return (layout, selection);
  }

  Future<void> longPressAt(WidgetTester tester, Offset position) async {
    final gesture = await tester.startGesture(position);
    await tester.pump(settings.longPressTimeout + const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pump();
  }

  testWidgets('a long press subtracts the app bar and the pinned header', (tester) async {
    final (layout, selection) = await pumpSelector(tester, rowCount: 6, headerHeight: 80, appBarHeight: 40);

    await longPressAt(tester, const Offset(20, 160));

    // 160 - 40 (app bar) - 80 (header) = 40, i.e. the second row.
    expect(layout.lastPosition?.dy, 40);
    expect(selection.isSelected([1]), isTrue);
    expect(selection.isSelecting, isTrue);
  });

  testWidgets('without a header the press lands one header lower', (tester) async {
    final (layout, selection) = await pumpSelector(tester, rowCount: 6, headerHeight: 0, appBarHeight: 40);

    await longPressAt(tester, const Offset(20, 160));

    expect(layout.lastPosition?.dy, 120);
    expect(selection.isSelected([3]), isTrue);
  });

  testWidgets('a row outside the selectable list does not start a selection', (tester) async {
    final (layout, selection) = await pumpSelector(tester, rowCount: 3, headerHeight: 0, forcedItem: 99);

    await longPressAt(tester, const Offset(20, 20));

    expect(layout.lastPosition, isNotNull);
    expect(selection.isSelecting, isFalse);
    expect(selection.selectedItemCount, 0);
  });

  testWidgets('the selection scope keeps a press from the other grid', (tester) async {
    final (layout, selection) = await pumpSelector(
      tester,
      rowCount: 5,
      headerHeight: 0,
      sameSelectionScope: (item, selected) => item.isEven,
    );

    // Start the selection on row 0, extend it to row 2 (both even).
    await longPressAt(tester, const Offset(20, 20));
    await longPressAt(tester, const Offset(20, 100));
    expect(selection.isSelected([0, 2]), isTrue);

    // Row 3 is outside the scope: the press is ignored instead of adding it.
    await longPressAt(tester, const Offset(20, 140));
    expect(layout.lastPosition?.dy, 140);
    expect(selection.isSelected([3]), isFalse);
    expect(selection.selectedItemCount, 2);
  });
}
