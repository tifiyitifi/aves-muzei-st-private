import 'package:aves/features/meta_settings/data/catalog.dart';
import 'package:aves/features/meta_settings/data/def_visibility.dart';
import 'package:aves/features/meta_settings/model/enum/settings_category.dart';
import 'package:aves/features/meta_settings/view/category_meta.dart';
import 'package:aves/features/meta_settings/view/widgets/meta_settings_list_view.dart';
import 'package:aves/features/meta_settings/view/widgets/setting_row.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/widgets/common/basic/insets.dart';
import 'package:aves/widgets/common/basic/scaffold.dart';
import 'package:aves/widgets/common/behaviour/pop/scope.dart';
import 'package:aves/widgets/common/behaviour/pop/tv_navigation.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/navigation/tv_rail.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// TV (rail) layout of the metadata settings surface.
///
/// Mirrors the upstream `SettingsTvPage`, but builds the rail and the section
/// body from the fork's catalog categories.
class MetaSettingsTvPage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return AvesScaffold(
      body: AvesPopScope(
        handlers: [tvNavigationPopHandler],
        child: Row(
          children: [
            TvRail(
              controller: context.read<TvRailController>(),
            ),
            Expanded(
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  DirectionalSafeArea(
                    start: false,
                    bottom: false,
                    child: AppBar(
                      automaticallyImplyLeading: false,
                      title: Text(context.l10n.settingsPageTitle),
                      elevation: 0,
                      primary: false,
                    ),
                  ),
                  const Expanded(
                    child: _Content(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Content extends StatefulWidget {
  const new();

  @override
  State<_Content> createState() => _ContentState();
}

class _ContentState extends State<_Content> {
  final ValueNotifier<int> _indexNotifier = ValueNotifier(0);

  static final List<SettingsCategory> _categories = SettingsCategory.values.where((category) => metaSettingsDefsFor(category).isNotEmpty).toList();

  @override
  void dispose() {
    _indexNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: _indexNotifier,
      builder: (context, selectedIndex, child) {
        final rail = NavigationRail(
          extended: true,
          destinations: _categories
              .map((category) {
                final meta = metaCategoryMeta[category]!;
                return NavigationRailDestination(
                  icon: meta.icon(context),
                  label: Text(meta.title(context)),
                );
              })
              .toList(),
          selectedIndex: selectedIndex,
          onDestinationSelected: (index) => _indexNotifier.value = index,
          minExtendedWidth: TvRail.minExtendedWidth,
        );
        return LayoutBuilder(
          builder: (context, constraints) {
            return Row(
              children: [
                MediaQuery.removePadding(
                  context: context,
                  removeLeft: true,
                  removeTop: true,
                  removeRight: true,
                  removeBottom: true,
                  child: SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: constraints.maxHeight),
                      child: IntrinsicHeight(child: rail),
                    ),
                  ),
                ),
                Expanded(
                  child: MediaQuery.removePadding(
                    context: context,
                    removeLeft: !context.isRtl,
                    removeRight: context.isRtl,
                    child: _CategoryDefs(
                      category: _categories[selectedIndex],
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _CategoryDefs extends StatelessWidget {
  final SettingsCategory category;

  const new({required this.category});

  @override
  Widget build(BuildContext context) {
    // subscribe so the `not_tv` visibility filter re-evaluates when the layout toggles
    context.select<Settings, bool>((s) => s.useTvLayout);
    final defs = metaSettingsDefsFor(category).where((def) => DefVisibility.isVisible(def.availabilityKey)).toList();
    return MetaSettingsListView(
      key: ValueKey(category),
      children: defs.map((def) => SettingRow(key: ValueKey('meta-${def.key}'), def: def)).toList(),
    );
  }
}
