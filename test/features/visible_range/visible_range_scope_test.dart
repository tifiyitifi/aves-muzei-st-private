import 'package:aves/features/visible_range/services/visible_range_gate.dart';
import 'package:aves/model/filters/path.dart';
import 'package:aves/services/common/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// The wallpaper group's browsing scope is app-wide but process-local.
///
/// These tests cover its own lifecycle: group 0 falls back to the gallery range,
/// and a close drops it. The session that owns it — and therefore what counts as
/// a close — is covered by `grouped_wallpaper_session_test.dart`.
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
  });

  tearDown(() {
    VisibleRangeGate.overlay = null;
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
