import 'dart:async';

import 'package:aves/features/browse_only/services/browse_library.dart';
import 'package:aves/features/browse_only/services/browse_prefs.dart';
import 'package:aves/features/browse_only/view/browse_only_page.dart';
import 'package:aves/features/browse_only/view/browse_timeline_preview.dart';
import 'package:aves/l10n/l10n.dart';
import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:aves/model/filters/mime.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves/services/media/media_store_service.dart';
import 'package:aves/theme/durations.dart';
import 'package:aves/widgets/collection/collection_page.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/common/providers/media_query_data_provider.dart';
import 'package:aves/widgets/filter_grids/albums_page.dart';
import 'package:aves/widgets/navigation/nav_item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../common.dart';
import '../../../fake/media_store_service.dart';
import '../test_settings.dart';

/// The page chrome: the title it carries, the spinner and the failure it shows
/// before anything was read, and the strip that offers the rows past the preview
/// limit. The grid and the strip have their own tests; here the page has to prove
/// it wires them to the right state.
void main() {
  late FakeMediaStoreService mediaStore;
  late BrowseTestSettings testSettings;

  setUpAll(() async {
    await setUpAllServices();
  });

  setUp(() async {
    await setUpServices();
    testSettings = BrowseTestSettings();
    addTearDown(testSettings.dispose);
    mediaStore = getIt<MediaStoreService>() as FakeMediaStoreService;
    browseLibrary.clear();
    testSettings.bottomNavigationActions = const [
      AvesNavItem(route: CollectionPage.routeName),
      AvesNavItem(route: AlbumListPage.routeName),
    ];
  });

  tearDown(browseLibrary.clear);

  Widget app() => MultiProvider(
    providers: [
      ChangeNotifierProvider<Settings>.value(value: testSettings),
      Provider<DurationsData>.value(value: DurationsData.noAnimation()),
    ],
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQueryDataProvider(
        // The chrome is under test: the tiles do not need the image pipeline.
        child: BrowseOnlyPage(tileBuilder: _buildTestTile),
      ),
    ),
  );

  String titleOf(WidgetTester tester) {
    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    return (appBar.title! as Text).data!;
  }

  /// Opens the page and lets the first page read settle.
  Future<BuildContext> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    return tester.element(find.byType(BrowseOnlyPage));
  }

  testWidgets('the page loads the persisted browse sort', (tester) async {
    // Must run before any other pump in this file: the store reads once.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('browse_only.media_sort', BrowseMediaSort.name.name);

    await pumpPage(tester);

    expect(browsePrefs.isLoaded, isTrue);
    expect(browsePrefs.mediaSort, BrowseMediaSort.name);
  });

  testWidgets('the title follows the navigation item that owns the view', (tester) async {
    final context = await pumpPage(tester);

    // The user's own timeline entry names the view, not a name invented here.
    expect(titleOf(tester), testSettings.bottomNavigationActions.first.getText(context));
  });

  testWidgets('a view with no navigation item of its own keeps the built-in name', (tester) async {
    // Neither entry can be served as the timeline, so nothing names it.
    testSettings.bottomNavigationActions = [
      AvesNavItem(route: CollectionPage.routeName, filters: {MimeFilter.video}),
      const AvesNavItem(route: AlbumListPage.routeName),
    ];

    final context = await pumpPage(tester);

    expect(titleOf(tester), context.l10n.browseOnlyTimelineTab);
  });

  testWidgets('the first read shows progress and then the empty library', (tester) async {
    mediaStore.pageHold = Completer<void>();

    await tester.pumpWidget(app());
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    mediaStore.pageHold!.complete();
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(BrowseOnlyPage));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text(context.l10n.browseOnlyEmptyLibrary), findsOneWidget);
  });

  testWidgets('a failed first read says so and retries on demand', (tester) async {
    mediaStore.pageError = StateError('the media store is unavailable');
    final context = await pumpPage(tester);

    // A failed read is not an empty library.
    expect(find.text(context.l10n.browseOnlyMediaFailed), findsOneWidget);
    expect(find.text(context.l10n.browseOnlyEmptyLibrary), findsNothing);
    final requests = mediaStore.pageRequestCount;

    mediaStore.pageError = null;
    await tester.tap(find.text(context.l10n.collectionLoadingRetry));
    await tester.pumpAndSettle();

    expect(mediaStore.pageRequestCount, requests + 1);
    expect(find.text(context.l10n.browseOnlyMediaFailed), findsNothing);
  });

  testWidgets('the preview strip counts the rows the grid shows, not the rows read', (tester) async {
    // A full preview, of which ten rows sit in a folder the user hid.
    browseLibrary.addEntries([
      for (var i = 0; i < BrowseLibrary.previewRowLimit - 10; i++) FakeMediaStoreService.newImage('/album', 'file$i'),
      for (var i = 0; i < 10; i++) FakeMediaStoreService.newImage('/hidden', 'hidden$i'),
    ]);
    final previous = settings.hiddenFilters;
    settings.hiddenFilters = {StoredAlbumFilter('/hidden', null)};
    addTearDown(() => settings.hiddenFilters = previous);

    final context = await pumpPage(tester);

    expect(browseLibrary.atLimit, isTrue);
    expect(find.byType(BrowseTimelinePreview), findsOneWidget);
    // The hidden rows were read, so the window is at its limit, but the strip
    // states what the timeline shows: claiming the hidden ten would promise
    // tiles that are not on screen.
    expect(find.text(context.l10n.browseOnlyTimelinePreview(BrowseLibrary.previewRowLimit - 10)), findsOneWidget);
  });

  testWidgets('a failed page turns the strip action into a retry', (tester) async {
    // Rows already read stay on screen when the next read fails; the strip then
    // retries that page instead of offering more.
    browseLibrary.addEntries([FakeMediaStoreService.newImage('/album', 'file')]);
    mediaStore.pageError = StateError('the media store is unavailable');

    final context = await pumpPage(tester);

    expect(find.byType(BrowseTimelinePreview), findsOneWidget);
    final requests = mediaStore.pageRequestCount;

    mediaStore.pageError = null;
    await tester.tap(find.text(context.l10n.browseOnlyTimelineContinue));
    await tester.pumpAndSettle();

    expect(mediaStore.pageRequestCount, requests + 1);
    expect(find.byType(BrowseTimelinePreview), findsNothing);
  });
}

Widget _buildTestTile(BuildContext context, int position) => const ColoredBox(color: Color(0xFF3366CC));
