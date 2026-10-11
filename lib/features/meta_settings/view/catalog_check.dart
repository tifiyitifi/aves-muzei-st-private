import 'package:aves/features/meta_settings/data/catalog.dart';
import 'package:aves/features/meta_settings/data/catalog_validation.dart';
import 'package:aves/features/meta_settings/data/def_visibility.dart';
import 'package:aves/features/meta_settings/model/enum/settings_category.dart';
import 'package:aves/features/meta_settings/view/category_meta.dart';
import 'package:aves/features/meta_settings/view/editor_registry.dart';
import 'package:aves/features/meta_settings/view/page_registry.dart';

/// Runs the catalog's structural checks against the live registries, plus the
/// view-level requirement that every populated category has a header.
List<String> metaCatalogProblems() {
  final problems = validateMetaSettingsCatalog(
    metaSettingsCatalog,
    registeredEditorKeys: metaEditorRegistry.keys.toSet(),
    registeredAvailabilityKeys: DefVisibility.registeredKeys,
    registeredPageRouteNames: metaPageRegistry.keys.toSet(),
  );
  for (final category in SettingsCategory.values) {
    if (metaSettingsDefsFor(category).isNotEmpty && !metaCategoryMeta.containsKey(category)) {
      problems.add('category ${category.name} has defs but no category meta');
    }
  }
  return problems;
}
