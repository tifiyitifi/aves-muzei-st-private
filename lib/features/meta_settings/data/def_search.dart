import 'package:aves/features/meta_settings/model/setting_def.dart';

/// Resolves the setting keys a def is matched by: a single-setting def uses its
/// own `key`, a sub-page uses the keys of the page it opens.
typedef SettingDefKeys = List<String> Function(SettingDef def);

/// Returns how many of the most recent keys form the window used by the
/// "recently changed settings" suggestions.
///
/// Mirrors upstream `SettingsSearchDelegate._findOptimalRecentSettingKeyTakeCount`:
/// start from [targetDefCount] keys and grow the window until at least
/// [targetDefCount] defs match, so the section is neither empty nor flooded.
int recentSettingKeyTakeCount({
  required List<String> recentKeys,
  required Iterable<SettingDef> defs,
  required SettingDefKeys keysOf,
  int targetDefCount = 3,
}) {
  var found = false;
  final allCount = recentKeys.length;
  var takeCount = targetDefCount;
  while (takeCount < allCount && !found) {
    final keys = recentKeys.take(takeCount).toSet();
    found = defs.where((def) => keysOf(def).any(keys.contains)).length >= targetDefCount;
    if (!found) takeCount++;
  }
  return takeCount;
}
