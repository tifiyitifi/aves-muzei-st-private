import 'package:aves/features/meta_settings/data/catalog.dart';
import 'package:aves/features/meta_settings/model/enum/settings_category.dart';
import 'package:aves/features/meta_settings/view/catalog_check.dart';
import 'package:aves/features/meta_settings/view/category_meta.dart';
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

    test('defs are returned in sort order', () {
      final orders = metaSettingsDefsFor(SettingsCategory.display).map((def) => def.sortOrder).toList();
      final sorted = [...orders]..sort();
      expect(orders, orderedEquals(sorted));
    });
  });
}
