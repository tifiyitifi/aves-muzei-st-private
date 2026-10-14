import 'package:aves/features/meta_settings/data/catalog.dart';
import 'package:aves/features/meta_settings/data/def_visibility.dart';
import 'package:aves/features/meta_settings/model/enum/settings_category.dart';
import 'package:aves/features/meta_settings/view/category_meta.dart';
import 'package:aves/features/meta_settings/view/widgets/meta_settings_list_view.dart';
import 'package:aves/features/meta_settings/view/widgets/setting_row.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/common/identity/aves_expansion_tile.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

/// Catalog-driven body of the metadata settings surface.
class MetaSettingsView extends StatefulWidget {
  const new({super.key});

  @override
  State<MetaSettingsView> createState() => _MetaSettingsViewState();
}

class _MetaSettingsViewState extends State<MetaSettingsView> {
  final ValueNotifier<String?> _expandedNotifier = ValueNotifier(null);

  @override
  void dispose() {
    _expandedNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = SettingsCategory.values.where((category) => metaSettingsDefsFor(category).isNotEmpty);
    return MetaSettingsListView(
      children: categories.map((category) => _buildSection(context, category)).toList(),
    );
  }

  Widget _buildSection(BuildContext context, SettingsCategory category) {
    // subscribe so the `not_tv` visibility filter re-evaluates when the layout toggles
    context.select<Settings, bool>((s) => s.useTvLayout);
    final meta = metaCategoryMeta[category]!;
    final defs = metaSettingsDefsFor(category).where((def) => DefVisibility.isVisible(def.availabilityKey));
    return AvesExpansionTile(
      // key is expected by test driver; match the legacy section key so the
      // shared driver (e.g. tapping `section-language`) works on both surfaces
      key: Key('section-${category.name}'),
      value: 'meta-${category.name}',
      leading: meta.icon(context),
      title: meta.title(context),
      locale: context.knownLocale,
      expandedNotifier: _expandedNotifier,
      showHighlight: false,
      children: defs.map((def) => SettingRow(key: ValueKey('meta-${def.key}'), def: def)).toList(),
    );
  }
}
