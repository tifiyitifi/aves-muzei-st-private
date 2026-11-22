import 'package:aves/features/live_wallpaper_refill/refill_entry.dart';
import 'package:flutter_test/flutter_test.dart';

/// The headless refill's dispatch contract.
///
/// The isolate itself needs a Flutter engine and the native worker, but the
/// decision "which wallpaper handles this call, with which flags" is pure and
/// is what the worker relies on.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a known target receives the tap and the command', () async {
    final calls = <({bool advance, String? command})>[];
    final refills = {
      liveWallpaperTargetMuzei: ({required bool advance, String? command}) async => calls.add((advance: advance, command: command)),
    };

    final handled = await handleLiveWallpaperRefillCall(
      {'target': liveWallpaperTargetMuzei, 'advance': true, 'command': 'nextGroup'},
      refills: refills,
    );

    expect(handled, isTrue);
    expect(calls, hasLength(1));
    expect(calls.single.advance, isTrue);
    expect(calls.single.command, 'nextGroup');
  });

  test('advance is only true for a literal true', () async {
    final advances = <bool>[];
    final refills = {
      liveWallpaperTargetGrouped: ({required bool advance, String? command}) async => advances.add(advance),
    };

    await handleLiveWallpaperRefillCall({'target': liveWallpaperTargetGrouped, 'advance': 1}, refills: refills);
    await handleLiveWallpaperRefillCall({'target': liveWallpaperTargetGrouped}, refills: refills);

    expect(advances, [false, false]);
  });

  test('a missing command is null', () async {
    String? seen = 'unset';
    final refills = {
      liveWallpaperTargetMuzei: ({required bool advance, String? command}) async => seen = command,
    };

    await handleLiveWallpaperRefillCall({'target': liveWallpaperTargetMuzei}, refills: refills);

    expect(seen, isNull);
  });

  test('an unknown target is rejected', () async {
    await expectLater(
      handleLiveWallpaperRefillCall({'target': 'unknown'}, refills: {}),
      throwsArgumentError,
    );
  });

  test('a non-map argument is rejected', () async {
    await expectLater(handleLiveWallpaperRefillCall('refill'), throwsArgumentError);
    await expectLater(handleLiveWallpaperRefillCall(null), throwsArgumentError);
  });

  test('the default map knows both wallpapers', () {
    expect(resolveLiveWallpaperRefill(liveWallpaperTargetMuzei), isNotNull);
    expect(resolveLiveWallpaperRefill(liveWallpaperTargetGrouped), isNotNull);
    expect(() => resolveLiveWallpaperRefill('unknown'), throwsArgumentError);
  });

  test('registering without an AOT callback handle is a no-op', () async {
    // The host VM has no callback handle; the feature must skip instead of
    // failing the app start.
    await expectLater(registerLiveWallpaperRefillCallback(), completes);
  });
}
