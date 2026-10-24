import 'package:aves/features/meta_settings/data/catalog.dart';
import 'package:aves/features/meta_settings/model/enum/setting_widget_kind.dart';
import 'package:aves/features/meta_settings/model/enum/settings_category.dart';
import 'package:aves/features/meta_settings/model/page_keys.dart';
import 'package:aves/features/meta_settings/model/setting_ids.dart';
import 'package:aves/features/meta_settings/view/catalog_check.dart';
import 'package:aves/features/meta_settings/view/category_meta.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_prefetch_setting.dart';
import 'package:aves_model/aves_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('meta settings catalog', () {
    test('passes its structural checks', () {
      expect(metaCatalogProblems(), isEmpty);
    });

    test('keys are unique', () {
      final keys = metaSettingsCatalog.map((def) => def.key).toList();
      expect(keys.toSet().length, keys.length);
    });

    test('every populated category has a header', () {
      final populated = SettingsCategory.values.where((category) => metaSettingsDefsFor(category).isNotEmpty).toList();
      expect(populated, isNotEmpty);
      for (final category in populated) {
        expect(metaCategoryMeta.containsKey(category), isTrue, reason: 'missing header for ${category.name}');
      }
    });

    // Release gate: the v2 surface must render every category, otherwise the
    // settings page is incomplete for the default engine.
    test('every category is populated', () {
      for (final category in SettingsCategory.values) {
        expect(metaSettingsDefsFor(category), isNotEmpty, reason: '${category.name} is not migrated');
      }
    });

    test('Display is fully migrated', () {
      final keys = metaSettingsDefsFor(SettingsCategory.display).map((def) => def.key).toSet();
      expect(keys, {
        SettingKeys.themeBrightnessKey,
        SettingKeys.themeColorModeKey,
        SettingKeys.enableDynamicColorKey,
        SettingKeys.enableBlurEffectKey,
        SettingKeys.maxBrightnessKey,
        SettingKeys.displayRefreshRateModeKey,
        SettingKeys.forceTvLayoutKey,
      });
    });

    test('Language is fully migrated', () {
      final keys = metaSettingsDefsFor(SettingsCategory.language).map((def) => def.key).toSet();
      expect(keys, {
        SettingKeys.localeKey,
        SettingKeys.calendarKey,
        SettingKeys.coordinateFormatKey,
        SettingKeys.unitSystemKey,
        SettingKeys.forceWesternArabicNumeralsKey,
      });
    });

    test('Accessibility is fully migrated', () {
      final keys = metaSettingsDefsFor(SettingsCategory.accessibility).map((def) => def.key).toSet();
      expect(keys, {
        SettingKeys.showPinchGestureAlternativesKey,
        SettingKeys.accessibilityAnimationsKey,
        SettingKeys.timeToTakeActionKey,
      });
    });

    test('Privacy is fully migrated', () {
      final keys = metaSettingsDefsFor(SettingsCategory.privacy).map((def) => def.key).toSet();
      expect(keys, {
        MetaPageKeys.permissions,
        MetaPageKeys.hiddenItems,
        MetaPageKeys.storageAccess,
        SettingKeys.enableBinKey,
        SettingKeys.saveSearchHistoryKey,
        SettingKeys.autoExportPathKey,
      });
    });

    test('Viewer is fully migrated', () {
      final keys = metaSettingsDefsFor(SettingsCategory.viewer).map((def) => def.key).toSet();
      expect(keys, {
        MetaPageKeys.viewerActions,
        MetaPageKeys.viewerOverlay,
        MetaPageKeys.viewerSlideshow,
        SettingKeys.viewerGestureSideTapNextKey,
        SettingKeys.viewerUseCutoutKey,
        SettingKeys.enableMotionPhotoAutoPlayKey,
        SettingKeys.imageBackgroundKey,
      });
    });

    test('Video is fully migrated', () {
      final keys = metaSettingsDefsFor(SettingsCategory.video).map((def) => def.key).toSet();
      expect(keys, {
        MetaSettingIds.videoShowVideos,
        MetaPageKeys.videoPlayback,
        MetaPageKeys.videoControls,
        MetaPageKeys.subtitleTheme,
        SettingKeys.videoThumbnailMethodsKey,
      });
    });

    test('Thumbnails is fully migrated', () {
      final keys = metaSettingsDefsFor(SettingsCategory.thumbnails).map((def) => def.key).toSet();
      expect(keys, {
        MetaPageKeys.collectionActions,
        MetaPageKeys.thumbnailOverlay,
        SettingKeys.collectionBurstPatternsKey,
      });
    });

    test('Navigation is fully migrated', () {
      final keys = metaSettingsDefsFor(SettingsCategory.navigation).map((def) => def.key).toSet();
      expect(keys, {
        SettingKeys.homePageKey,
        SettingKeys.keepScreenOnKey,
        SettingKeys.mustBackTwiceToExitKey,
        MetaPageKeys.navigationDrawer,
        MetaPageKeys.bottomNavActions,
        MetaPageKeys.confirmationDialog,
      });
    });

    test('defs are returned in sort order', () {
      final orders = metaSettingsDefsFor(SettingsCategory.display).map((def) => def.sortOrder).toList();
      final sorted = [...orders]..sort();
      expect(orders, orderedEquals(sorted));
    });

    // The deeper pre-bake is a trade-off (disk and effect rebakes), so it must
    // stay a plain default-on toggle whose subtitle states the cost.
    test('the wallpaper prefetch option is a default-on toggle', () {
      final def = metaSettingsCatalog.singleWhere((def) => def.key == WallpaperPrefetchSetting.key);
      expect(def.category, SettingsCategory.advanced);
      expect(def.widgetKind, SettingWidgetKind.toggle);
      expect(def.mutator, isNull);
      expect(def.reader, isNotNull);
      expect(def.subtitle, isNotNull, reason: 'the subtitle must state the resource cost');
      expect(WallpaperPrefetchSetting.defaultValue, isTrue);
    });
  });
}
