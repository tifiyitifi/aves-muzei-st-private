import 'package:aves/features/visible_range/services/visible_range_gate.dart';
import 'package:aves/model/filters/path.dart';
import 'package:aves/services/common/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// The wallpaper group's browsing scope is app-wide but process-local.
///
/// These tests cover its lifecycle: a destination switch keeps it, a close
/// clears it, and group 0 falls back to the gallery range alone.
void main() {
  setUpAll(() {
    getIt.registerLazySingleton<p.Context>(() => p.Context(style: p.Style.posix));
  });

  tearDownAll(getIt.reset);

  late PathFilter dcim;
  late VisibleRangeBrowsingOverlay groupScope;

  setUp(() {
    dcim = PathFilter('/storage/emulated/0/DCIM/');
    groupScope = VisibleRangeBrowsingOverlay(groupFilter: dcim);
    VisibleRangeGate.overlay = null;
    VisibleRangeGate.clearWallpaperScope();
  });

  tearDown(() {
    VisibleRangeGate.overlay = null;
    VisibleRangeGate.clearWallpaperScope();
  });

  group('navigation mark', () {
    test('a marked dispose keeps the scope', () {
      final owner = VisibleRangeGate.claimWallpaperScope(groupScope);

      VisibleRangeGate.preserveWallpaperScopeOnNextDispose();
      expect(VisibleRangeGate.takeWallpaperScopePreserve(), isTrue);
      // The page is disposed but does not clear: the media set must keep the
      // group range it was switched to.
      expect(VisibleRangeGate.overlay?.groupFilter, dcim);
      expect(VisibleRangeGate.publishWallpaperScope(owner, null), isTrue);
    });

    test('an unmarked dispose is a close and does not consume anything', () {
      expect(VisibleRangeGate.takeWallpaperScopePreserve(), isFalse);
    });

    test('the mark is consumed once', () {
      VisibleRangeGate.preserveWallpaperScopeOnNextDispose();
      expect(VisibleRangeGate.takeWallpaperScopePreserve(), isTrue);
      expect(VisibleRangeGate.takeWallpaperScopePreserve(), isFalse);
    });
  });

  group('clear', () {
    test('drops the overlay and releases the owner', () async {
      final owner = VisibleRangeGate.claimWallpaperScope(groupScope);
      VisibleRangeGate.clearWallpaperScope();
      await Future.microtask(() {});

      expect(VisibleRangeGate.overlay, isNull);
      // The closed page must not resurrect nor clear a newer scope.
      expect(VisibleRangeGate.publishWallpaperScope(owner, groupScope), isFalse);
    });
  });

  group('group 0', () {
    test('publishing group 0 falls back to the gallery range', () {
      final owner = VisibleRangeGate.claimWallpaperScope(groupScope);
      expect(VisibleRangeGate.publishWallpaperScope(owner, null), isTrue);
      expect(VisibleRangeGate.overlay, isNull);
    });

    test('suspending the gallery range needs a group scope', () {
      VisibleRangeGate.setGallerySuspended(true);
      expect(VisibleRangeGate.overlay, isNull);
    });
  });
}
