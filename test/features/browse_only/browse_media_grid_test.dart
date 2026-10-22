import 'package:aves/features/browse_only/services/browse_library.dart';
import 'package:aves/features/browse_only/services/browse_prefs.dart';
import 'package:aves/features/browse_only/view/browse_media_grid.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/widgets/common/basic/draggable_scrollbar/scrollbar.dart';
import 'package:aves/widgets/common/providers/media_query_data_provider.dart';
import 'package:aves_model/aves_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../common.dart';

/// The settings the grid theme reads, without the device behind them.
///
/// `GridTheme` asks `settings.useTvLayout`, which asks the device whether it is
/// a television, and the device singleton is filled from platform plugins the
/// tests do not run. Everything else the tree reads is left at its default.
class _SettingsWithoutDevice extends ChangeNotifier implements Settings {
  @override
  bool get useTvLayout => false;

  @override
  bool get showThumbnailFavourite => false;

  @override
  bool get showThumbnailHdr => false;

  @override
  ThumbnailOverlayLocationIcon get thumbnailLocationIcon => .none;

  @override
  ThumbnailOverlayTagIcon get thumbnailTagIcon => .none;

  @override
  bool get showThumbnailMotionPhoto => false;

  @override
  bool get showThumbnailRating => false;

  @override
  bool get showThumbnailRaw => false;

  @override
  bool get showThumbnailVideoDuration => false;

  @override
  bool get animate => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName} on the test settings');
}

/// A tile with no image behind it: the layout is what is under test.
class _TestTile extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => const ColoredBox(color: Color(0xFF3366CC));
}

/// The sectioned grid is one list: a month header, then the rows of tiles under
/// it.
///
/// The header is not pinned on purpose. A pinned header of a fixed extent never
/// shrinks, so it keeps painting after its own extent is spent and the viewport
/// pushes every following sliver down by its height: with a section per sliver,
/// the headers pile up over the content as they are scrolled past, until the
/// screen is headers.
void main() {
  late BrowseLibrary library;
  late _SettingsWithoutDevice testSettings;

  setUpAll(() async {
    await setUpAllServices();
    // the month headers format their date with the app's locale
    await initializeDateFormatting();
  });

  setUp(() async {
    await setUpServices();
    testSettings = _SettingsWithoutDevice();
    addTearDown(testSettings.dispose);
    library = BrowseLibrary();
  });

  tearDown(() {
    library.dispose();
  });

  AvesEntry entry(int id, int dateTakenMillis) => AvesEntry(
    id: id,
    uri: 'content://$id',
    path: '/album/$id.jpg',
    contentId: 100 + id,
    pageId: null,
    sourceMimeType: 'image/jpeg',
    width: 10,
    height: 20,
    sourceRotationDegrees: 0,
    sizeBytes: 5,
    sourceTitle: 'title$id',
    dateAddedSecs: 1,
    dateModifiedMillis: 2,
    sourceDateTakenMillis: dateTakenMillis,
    durationMillis: 0,
    trashed: false,
    origin: EntryOrigins.mediaStoreContent,
  );

  /// A month of rows, long enough to fill a screen at any column count the grid
  /// can pick, so the month after it is a scroll away rather than a header away.
  Iterable<AvesEntry> month(int month, int firstId) sync* {
    final newest = DateTime.utc(2026, month, 20).millisecondsSinceEpoch;
    for (var i = 0; i < 400; i++) {
      yield entry(firstId + i, newest - i * 60000);
    }
  }

  Widget app() => MultiProvider(
    providers: [ChangeNotifierProvider<Settings>.value(value: testSettings)],
    child: MaterialApp(
      home: MediaQueryDataProvider(
        child: Scaffold(
          body: BrowseMediaGrid(
            library: library,
            indexes: library.mediaIndexes(sort: BrowseMediaSort.date, reverse: false),
            tileBuilder: (context, position) => const _TestTile(),
          ),
        ),
      ),
    ),
  );

  testWidgets('the month header scrolls away with the rows under it', (tester) async {
    library.addEntries([
      ...month(9, 1000),
      ...month(8, 2000),
      ...month(7, 3000),
    ]);

    await tester.pumpWidget(app());
    await tester.pump();

    // The newest month is the only header on screen: the months below it are a
    // whole month away, not stacked over it.
    final header = find.byType(BrowseMonthHeader);
    expect(header, findsOneWidget);
    expect(tester.widget<BrowseMonthHeader>(header).month, 9);

    // The rows are square and start under the header.
    final tile = find.byType(_TestTile).first;
    final tileSize = tester.getSize(tile);
    expect(tileSize.width, greaterThan(0));
    expect(tileSize.width, moreOrLessEquals(tileSize.height));
    expect(tester.getRect(tile).top, greaterThanOrEqualTo(tester.getRect(header).bottom - .01));

    // At the end of the grid the last month's rows are on screen and every
    // header has scrolled away with the rows it belongs to.
    final position = tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();

    expect(find.byType(BrowseMonthHeader), findsNothing);
    expect(find.byType(_TestTile), findsWidgets);
  });

  testWidgets('a long timeline gets the drag handle, and a drag lands on a month', (tester) async {
    // The handle is for a timeline long enough that either end is more than a
    // flick away: five months.
    library.addEntries([
      ...month(9, 1000),
      ...month(8, 2000),
      ...month(7, 3000),
      ...month(6, 4000),
      ...month(5, 5000),
    ]);

    await tester.pumpWidget(app());
    await tester.pump();

    expect(find.byType(DraggableScrollbar), findsOneWidget);
    final position = tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    expect(position.pixels, 0);

    // The handle fades in with a scroll and out again after a moment, as a
    // scrollbar does: reveal it the way a scroll does before grabbing it.
    position.jumpTo(200);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Grab the handle at the top of the right edge and pull it down: the drag
    // jumps the timeline instead of scrolling it pixel by pixel.
    final size = tester.getSize(find.byType(BrowseMediaGrid));
    await tester.dragFrom(Offset(size.width - 12, 24), const Offset(0, 240));
    await tester.pump();

    expect(position.pixels, greaterThan(200));
  });
}
