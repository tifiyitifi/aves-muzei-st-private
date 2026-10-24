import 'package:aves/features/muzei_wallpaper/model/wallpaper_auto_advance.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_display.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_effects.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_gestures.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_source_kind.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_source_scope.dart';
import 'package:aves/features/muzei_wallpaper/services/wallpaper_prefs.dart';
import 'package:aves/model/filters/favourite.dart';
import 'package:aves/model/filters/mime.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('starts on Muzei-compatible defaults', () async {
    final prefs = WallpaperPrefs();
    await prefs.init();

    expect(prefs.scope.kind, WallpaperSourceKind.myPhotos);
    expect(prefs.scope.filters, isEmpty);
    expect(prefs.scope.singleEntryId, isNull);
    expect(prefs.effects, const WallpaperEffectsConfig());
    expect(prefs.gestures, const WallpaperGestures());
    expect(prefs.autoAdvance.interval, WallpaperInterval.never);
    expect(prefs.autoAdvance.ordering, WallpaperOrdering.newThenRandom);
    expect(prefs.lastAdvancedAt, isNull);
    expect(prefs.currentIndex, 0);
    expect(prefs.viewportZoom, 1);
    expect(prefs.isLoaded, isTrue);
    prefs.dispose();
  });

  test('persists and reloads every setting', () async {
    final prefs = WallpaperPrefs();
    await prefs.init();
    await prefs.setSourceScope(
      WallpaperSourceScope(
        kind: WallpaperSourceKind.single,
        filters: {FavouriteFilter.instance, MimeFilter.image},
        singleEntryId: 42,
      ),
    );
    await prefs.setEffects(
      const WallpaperEffectsConfig(
        home: WallpaperEffects(blur: 10, dim: 20, grey: 30),
        lock: WallpaperEffects(blur: 40, dim: 50, grey: 60),
        link: true,
      ),
    );
    await prefs.setGestures(
      const WallpaperGestures(
        doubleTap: WallpaperTapAction.nextArtwork,
        threeFinger: WallpaperTapAction.viewArtwork,
      ),
    );
    await prefs.setAutoAdvance(
      const WallpaperAutoAdvance(
        interval: WallpaperInterval.h3,
        ordering: WallpaperOrdering.inOrder,
      ),
    );
    await prefs.setLastAdvancedAt(1700000000000);
    await prefs.setCurrentIndex(5);
    await prefs.setViewport(x: 0.2, y: -0.1, zoom: 2.5);
    await prefs.setTitleMode(WallpaperTitleMode.sourceName);
    prefs.dispose();

    final reloaded = WallpaperPrefs();
    await reloaded.init();
    expect(reloaded.scope.kind, WallpaperSourceKind.single);
    expect(reloaded.scope.filters, {FavouriteFilter.instance, MimeFilter.image});
    expect(reloaded.scope.singleEntryId, 42);
    expect(reloaded.effects.home.blur, 10);
    expect(reloaded.effects.lock.grey, 60);
    expect(reloaded.effects.link, isTrue);
    expect(reloaded.gestures.doubleTap, WallpaperTapAction.nextArtwork);
    expect(reloaded.gestures.threeFinger, WallpaperTapAction.viewArtwork);
    expect(reloaded.autoAdvance.interval, WallpaperInterval.h3);
    expect(reloaded.autoAdvance.ordering, WallpaperOrdering.inOrder);
    expect(reloaded.lastAdvancedAt, 1700000000000);
    expect(reloaded.currentIndex, 5);
    expect(reloaded.viewportX, 0.2);
    expect(reloaded.viewportY, -0.1);
    expect(reloaded.viewportZoom, 2.5);
    expect(reloaded.titleMode, WallpaperTitleMode.sourceName);
    reloaded.dispose();
  });

  test('clamps persisted out-of-range values', () async {
    SharedPreferences.setMockInitialValues({
      WallpaperPrefsKeys.effectsHomeBlur: -100,
      WallpaperPrefsKeys.effectsHomeDim: 999,
      WallpaperPrefsKeys.effectsHomeGrey: 999,
      WallpaperPrefsKeys.autoIntervalSeconds: 12345,
      WallpaperPrefsKeys.viewportZoom: 99.0,
      WallpaperPrefsKeys.currentIndex: -5,
    });

    final prefs = WallpaperPrefs();
    await prefs.init();
    expect(prefs.effects.home.blur, 0);
    expect(prefs.effects.home.dim, WallpaperEffects.maxDim);
    expect(prefs.effects.home.grey, WallpaperEffects.maxGrey);
    expect(prefs.autoAdvance.interval, WallpaperInterval.never);
    expect(prefs.viewportZoom, WallpaperPrefs.maxViewportZoom);
    expect(prefs.currentIndex, 0);
    expect(prefs.titleMode, WallpaperTitleMode.defaultMode);
    prefs.dispose();
  });

  test('clearing the single id removes it from storage', () async {
    final prefs = WallpaperPrefs();
    await prefs.init();
    await prefs.setSingleEntryId(9);
    expect(prefs.scope.singleEntryId, 9);
    await prefs.setSingleEntryId(null);

    final reloaded = WallpaperPrefs();
    await reloaded.init();
    expect(reloaded.scope.singleEntryId, isNull);
    prefs.dispose();
    reloaded.dispose();
  });

  test('invalid enum names fall back to defaults', () async {
    SharedPreferences.setMockInitialValues({
      WallpaperPrefsKeys.gesturesDoubleTap: 'bogus',
      WallpaperPrefsKeys.autoOrdering: 'bogus',
      WallpaperPrefsKeys.sourceKind: 'bogus',
    });

    final prefs = WallpaperPrefs();
    await prefs.init();
    expect(prefs.gestures.doubleTap, WallpaperGestures.defaultDoubleTap);
    expect(prefs.autoAdvance.ordering, WallpaperAutoAdvance.defaultOrdering);
    expect(prefs.scope.kind, WallpaperSourceKind.myPhotos);
    prefs.dispose();
  });
}
