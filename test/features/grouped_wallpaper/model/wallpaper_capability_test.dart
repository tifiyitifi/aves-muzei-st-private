import 'package:aves/features/grouped_wallpaper/model/wallpaper_capability.dart';
import 'package:flutter_test/flutter_test.dart';

/// The one place that may narrow a frame from elsewhere: a wrong
/// `unsupported` would remove a working phone's scroll effect.
void main() {
  WallpaperCapability capability({
    WallpaperHost host = WallpaperHost.none,
    String launcher = 'com.example.launcher',
    int? span,
    double? step,
    bool moved = false,
  }) => WallpaperCapability(
    host: host,
    launcherPackage: launcher,
    deviceModel: 'Test Model',
    scrollSpan: span,
    scrollStep: step,
    scrollOffsetMoved: moved,
  );

  group('panVerdict', () {
    test('a lock-only host never pans', () {
      for (final step in [null, 0.0, 0.25]) {
        final verdict = capability(host: WallpaperHost.lock, step: step).panVerdict;
        expect(verdict, CapabilityVerdict.unsupported, reason: 'step=$step');
      }
    });

    test('an unbound host is unknown and keeps the wide frame', () {
      final c = capability(host: WallpaperHost.none, step: 0);
      expect(c.panVerdict, CapabilityVerdict.unknown);
      expect(c.bakesWide, isTrue);
    });

    test('a home host with no measurement yet is unknown and keeps the wide frame', () {
      final c = capability(host: WallpaperHost.home);
      expect(c.panVerdict, CapabilityVerdict.unknown);
      expect(c.bakesWide, isTrue);
    });

    test('a home host whose launcher reports no step cannot pan', () {
      final c = capability(host: WallpaperHost.home, step: 0);
      expect(c.panVerdict, CapabilityVerdict.unsupported);
      expect(c.bakesWide, isFalse);
    });

    test('a both host whose launcher reports no step cannot pan', () {
      expect(capability(host: WallpaperHost.both, step: 0).bakesWide, isFalse);
    });

    test('a real step proves the launcher pans', () {
      final c = capability(host: WallpaperHost.home, step: 0.25);
      expect(c.panVerdict, CapabilityVerdict.supported);
      expect(c.bakesWide, isTrue);
    });

    test('a positive step wins over the system scroll setting', () {
      // A launcher visibly panning is first-hand evidence; an OEM switch left
      // at "no scroll" must not take the effect away from it.
      final c = capability(host: WallpaperHost.home, span: 0, step: 0.5);
      expect(c.panVerdict, CapabilityVerdict.supported);
      expect(c.bakesWide, isTrue);
    });

    test('the system scroll setting narrows an unmeasured launcher', () {
      final c = capability(host: WallpaperHost.home, span: 0);
      expect(c.panVerdict, CapabilityVerdict.unsupported);
      expect(c.bakesWide, isFalse);
    });

    test('a moving offset proves panning even when the step stays zero', () {
      // Some launchers scroll the wallpaper while reporting no step; narrowing
      // them would visibly kill a working effect, so the offset wins.
      final c = capability(host: WallpaperHost.home, span: 0, step: 0, moved: true);
      expect(c.panVerdict, CapabilityVerdict.supported);
      expect(c.bakesWide, isTrue);
    });

    test('a launcher that pans on a both host keeps the wide frame', () {
      expect(capability(host: WallpaperHost.both, step: 1).bakesWide, isTrue);
    });
  });

  group('hostVerdict', () {
    test('a home host is supported even on a known fixed-wallpaper launcher', () {
      final c = capability(host: WallpaperHost.home, launcher: 'com.miui.home');
      expect(c.hostVerdict, CapabilityVerdict.supported);
      expect(c.warnsBeforeApply, isFalse);
    });

    test('MIUI without a home host warns', () {
      final c = capability(host: WallpaperHost.none, launcher: 'com.miui.home');
      expect(c.hostVerdict, CapabilityVerdict.unsupported);
      expect(c.warnsBeforeApply, isTrue);
    });

    test('MIUI bound to the lock screen warns', () {
      final c = capability(host: WallpaperHost.lock, launcher: 'com.miui.home');
      expect(c.hostVerdict, CapabilityVerdict.unsupported);
      expect(c.warnsBeforeApply, isTrue);
      // That host is measured too, so the warning can promise the narrow frame.
      expect(c.bakesWide, isFalse);
    });

    test('MIUI with no home host warns without promising a narrow frame', () {
      final c = capability(host: WallpaperHost.none, launcher: 'com.miui.home');
      expect(c.warnsBeforeApply, isTrue);
      // Nothing is measured yet, so the first bake is still wide: the dialog must
      // not say it will use screen-sized frames.
      expect(c.bakesWide, isTrue);
    });

    test('an unknown launcher with no home host is not warned about', () {
      final c = capability(host: WallpaperHost.none, launcher: 'com.example.launcher');
      expect(c.hostVerdict, CapabilityVerdict.unknown);
      expect(c.warnsBeforeApply, isFalse);
    });
  });

  group('parse', () {
    test('a missing answer is unknown, never unsupported', () {
      expect(WallpaperCapability.parse(null).panVerdict, CapabilityVerdict.unknown);
      expect(WallpaperCapability.unknown.bakesWide, isTrue);
    });

    test('reads the native map', () {
      final c = WallpaperCapability.parse({
        'host': 'lock',
        'launcher': 'com.miui.home',
        'model': '25060RK16C',
        'scrollSpan': 0,
        'scrollStep': null,
      });
      expect(c.host, WallpaperHost.lock);
      expect(c.launcherPackage, 'com.miui.home');
      expect(c.deviceModel, '25060RK16C');
      expect(c.scrollSpan, 0);
      expect(c.scrollStep, isNull);
      expect(c.warningKey, '25060RK16C|com.miui.home');
    });

    test('an unknown host name degrades to none', () {
      expect(WallpaperCapability.parse({'host': 'somewhere'}).host, WallpaperHost.none);
    });
  });
}
