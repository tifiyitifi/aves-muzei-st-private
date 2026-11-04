import 'package:aves/features/grouped_wallpaper/services/grouped_wallpaper_nav_controller.dart';
import 'package:aves/features/grouped_wallpaper/services/grouped_wallpaper_session.dart';
import 'package:aves/features/visible_range/services/visible_range_gate.dart';
import 'package:aves/model/filters/path.dart';
import 'package:aves/services/common/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Closing the wallpaper page is one path, shared by the page's own action and
/// the navigation settings: it must end the session and drop the browsing scope
/// that came with it.
void main() {
  setUpAll(() {
    getIt.registerLazySingleton<p.Context>(() => p.Context(style: p.Style.posix));
  });

  tearDownAll(getIt.reset);

  late PathFilter group;
  late VisibleRangeBrowsingOverlay scope;

  setUp(() {
    group = PathFilter('/b');
    scope = VisibleRangeBrowsingOverlay(groupFilter: group);
    VisibleRangeGate.overlay = null;
    groupedWallpaperNavController.closeSession();
  });

  tearDown(() {
    VisibleRangeGate.overlay = null;
    groupedWallpaperNavController.closeSession();
  });

  test('closing from the page ends the session and releases its scope', () async {
    groupedWallpaperNavController.openSession();
    final owner = VisibleRangeGate.claimWallpaperScope(scope);

    closeGroupedWallpaperSession(owner: owner);
    await Future.microtask(() {});

    expect(groupedWallpaperNavController.sessionActive, isFalse);
    expect(VisibleRangeGate.overlay, isNull);
  });

  test('closing from the settings needs no page to release', () async {
    groupedWallpaperNavController.openSession();
    // The page that published the scope was already left, so nobody holds its
    // token any more.
    VisibleRangeGate.claimWallpaperScope(scope);

    closeGroupedWallpaperSession();
    await Future.microtask(() {});

    expect(groupedWallpaperNavController.sessionActive, isFalse);
    expect(VisibleRangeGate.overlay, isNull);
  });

  test('a stale page cannot clear a newer page\'s scope', () async {
    groupedWallpaperNavController.openSession();
    final stale = VisibleRangeGate.claimWallpaperScope(scope);
    final current = VisibleRangeGate.claimWallpaperScope(scope);

    closeGroupedWallpaperSession(owner: stale);
    await Future.microtask(() {});

    expect(VisibleRangeGate.overlay?.groupFilter, group);

    // The page that actually owns the scope still closes it.
    closeGroupedWallpaperSession(owner: current);
    await Future.microtask(() {});

    expect(VisibleRangeGate.overlay, isNull);
  });
}
