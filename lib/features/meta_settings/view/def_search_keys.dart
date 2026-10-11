import 'package:aves/features/meta_settings/model/page_keys.dart';
import 'package:aves/features/meta_settings/model/setting_def.dart';
import 'package:aves/features/meta_settings/model/setting_ids.dart';
import 'package:aves/features/meta_settings/view/page_search_keys.dart';
import 'package:aves/widgets/settings/privacy/permissions/permissions_page.dart';
import 'package:aves_model/aves_model.dart';

/// Setting keys of catalog entries whose `SettingDef.key` is not the key they
/// actually persist.
///
/// A custom editor may flip another setting or open a page, so matching it by
/// its own `key` never surfaces it under "recently changed settings". These
/// aliases mirror the upstream tiles' `settingKeys`; a def absent here is
/// matched by its own `key`.
const Map<String, List<String>> metaDefSearchKeys = {
  MetaPageKeys.permissions: PermissionsPage.settingKeys,
  MetaSettingIds.videoShowVideos: [
    SettingKeys.hiddenFiltersKey,
    SettingKeys.deactivatedHiddenFiltersKey,
  ],
};

/// Resolves the setting keys a def is matched by in settings search: a sub-page
/// uses the keys of the page it opens, an aliased custom def uses [metaDefSearchKeys],
/// and everything else its own `key`.
List<String> metaSearchKeysOf(SettingDef def) {
  final routeName = def.routeName;
  if (routeName != null) return metaPageSearchKeys[routeName] ?? const [];
  return metaDefSearchKeys[def.key] ?? [def.key];
}
