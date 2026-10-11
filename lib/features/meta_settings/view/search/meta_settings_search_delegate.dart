import 'package:aves/features/meta_settings/data/catalog.dart';
import 'package:aves/features/meta_settings/data/def_search.dart';
import 'package:aves/features/meta_settings/data/def_visibility.dart';
import 'package:aves/features/meta_settings/model/enum/settings_category.dart';
import 'package:aves/features/meta_settings/model/setting_def.dart';
import 'package:aves/features/meta_settings/view/category_meta.dart';
import 'package:aves/features/meta_settings/view/page_search_keys.dart';
import 'package:aves/features/meta_settings/view/widgets/setting_row.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/common/identity/empty.dart';
import 'package:aves/widgets/common/identity/highlight_title.dart';
import 'package:aves/widgets/common/providers/media_query_data_provider.dart';
import 'package:aves/widgets/common/search/delegate.dart';
import 'package:material_ui/material_ui.dart';

/// Catalog-driven settings search for the v2 surface.
///
/// Indexes the catalog defs (grouped by category) instead of the upstream
/// `SettingsSection` / `SettingsTile` abstraction.
class MetaSettingsSearchDelegate extends AvesSearchDelegate {
  static const pageRouteName = '/settings/search';

  new({
    required super.searchFieldLabel,
    required super.searchFieldStyle,
  }) : super(routeName: pageRouteName);

  @override
  Widget buildSuggestions(BuildContext context) {
    final upQuery = query.toUpperCase().trim();

    List<SettingDef> visibleDefs(SettingsCategory category) =>
        metaSettingsDefsFor(category).where((def) => DefVisibility.isVisible(def.availabilityKey)).toList();

    // A sub-page is matched by the keys of the page it opens, not by its own
    // `MetaPageKeys` route name (cf. upstream `SettingsTile.settingKeys`).
    List<String> keysOf(SettingDef def) {
      final routeName = def.routeName;
      return routeName != null ? (metaPageSearchKeys[routeName] ?? const []) : [def.key];
    }

    bool testTitle(String title) => title.toUpperCase().contains(upQuery);

    // Recently changed settings: the window over `recentSettingKeys` is grown
    // until enough defs match (same heuristic as the upstream search).
    final recentKeys = <String>[];
    if (upQuery.isEmpty) {
      final recent = settings.recentSettingKeys;
      final takeCount = recentSettingKeyTakeCount(
        recentKeys: recent,
        defs: SettingsCategory.values.expand(visibleDefs),
        keysOf: keysOf,
      );
      recentKeys.addAll(recent.take(takeCount));
    }

    final children = <Widget>[];
    for (final category in SettingsCategory.values) {
      final meta = metaCategoryMeta[category];
      if (meta == null) continue;

      final List<SettingDef> matched;
      if (upQuery.isEmpty) {
        matched = visibleDefs(category).where((def) => keysOf(def).any(recentKeys.contains)).toList();
      } else if (testTitle(meta.title(context))) {
        matched = visibleDefs(category);
      } else {
        matched = visibleDefs(category).where((def) => testTitle(def.title(context))).toList();
      }
      if (matched.isEmpty) continue;

      children
        ..add(
          Padding(
            // match header layout in the Settings page
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            child: Row(
              children: [
                meta.icon(context),
                const SizedBox(width: 8),
                Expanded(
                  child: HighlightTitle(
                    title: meta.title(context),
                    locale: context.knownLocale,
                    showHighlight: false,
                  ),
                ),
              ],
            ),
          ),
        )
        ..addAll(matched.map((def) => SettingRow(key: ValueKey('meta-${def.key}'), def: def)));
    }

    return MediaQueryDataProvider(
      child: SafeArea(
        child: children.isEmpty
            ? EmptyContent(
                icon: AIcons.settings,
                text: context.l10n.settingsSearchEmpty,
              )
            : ListView(
                padding: const EdgeInsets.all(8),
                children: children,
              ),
      ),
    );
  }

  @override
  Widget buildResults(BuildContext context) => buildSuggestions(context);
}
