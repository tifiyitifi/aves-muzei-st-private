import 'package:aves/features/meta_settings/data/catalog.dart';
import 'package:aves/features/meta_settings/model/enum/setting_widget_kind.dart';
import 'package:aves/features/meta_settings/model/enum/settings_category.dart';
import 'package:aves/features/meta_settings/model/page_keys.dart';
import 'package:aves/features/meta_settings/model/setting_def.dart';
import 'package:aves/features/meta_settings/model/setting_ids.dart';
import 'package:aves/features/meta_settings/view/def_search_keys.dart';
import 'package:aves/features/meta_settings/view/page_search_keys.dart';
import 'package:aves/widgets/settings/privacy/permissions/permissions_page.dart';
import 'package:aves_model/aves_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// The custom-def aliases must match what the editors actually persist, so a
/// change made through one of them surfaces under "recently changed settings".
void main() {
  SettingDef def(String key, {String? routeName, SettingWidgetKind kind = SettingWidgetKind.toggle}) => SettingDef(
    key: key,
    category: SettingsCategory.display,
    widgetKind: kind,
    title: (context) => key,
    routeName: routeName,
  );

  group('metaSearchKeysOf', () {
    test('a plain def resolves to its own key', () {
      expect(metaSearchKeysOf(def(SettingKeys.enableBinKey)), [SettingKeys.enableBinKey]);
    });

    test('a sub-page resolves through the page search keys', () {
      final result = metaSearchKeysOf(def(MetaPageKeys.viewerOverlay, routeName: MetaPageKeys.viewerOverlay, kind: SettingWidgetKind.subPage));
      expect(result, metaPageSearchKeys[MetaPageKeys.viewerOverlay]);
      expect(result, isNotEmpty);
    });

    test('the permissions entry resolves to the keys its page writes', () {
      final permissionsDef = metaSettingsCatalog.firstWhere((d) => d.key == MetaPageKeys.permissions);
      expect(metaSearchKeysOf(permissionsDef), PermissionsPage.settingKeys);
    });

    test('the videoShowVideos entry resolves to the hidden-filter keys', () {
      final videosDef = metaSettingsCatalog.firstWhere((d) => d.key == MetaSettingIds.videoShowVideos);
      expect(metaSearchKeysOf(videosDef), [SettingKeys.hiddenFiltersKey, SettingKeys.deactivatedHiddenFiltersKey]);
    });
  });
}
