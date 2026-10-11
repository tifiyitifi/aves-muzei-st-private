import 'package:aves/features/meta_settings/engine/meta_settings_engine.dart';
import 'package:aves/features/meta_settings/model/enum/setting_widget_kind.dart';
import 'package:aves/features/meta_settings/model/setting_def.dart';
import 'package:aves/features/meta_settings/view/editor_registry.dart';
import 'package:aves/features/meta_settings/view/page_registry.dart';
import 'package:aves/features/meta_settings/view/widgets/meta_selection_list_tile.dart';
import 'package:aves/features/meta_settings/view/widgets/meta_sub_page_tile.dart';
import 'package:aves/features/meta_settings/view/widgets/meta_switch_list_tile.dart';
import 'package:flutter/widgets.dart';

/// Renders one catalog def by dispatching on its widget kind.
class SettingRow extends StatelessWidget {
  final SettingDef def;

  const new({super.key, required this.def});

  @override
  Widget build(BuildContext context) {
    switch (def.widgetKind) {
      case SettingWidgetKind.toggle:
        return MetaSwitchListTile(
          selector: (context, settings) => def.reader!(settings) as bool,
          onChanged: (value) => metaSettingsEngine.apply(def, value),
          title: def.title,
          subtitle: def.subtitle,
        );
      case SettingWidgetKind.enumPick:
        return MetaSelectionListTile<Enum>(
          values: def.enumValues!,
          getName: (context, value) => def.enumName!(context, value),
          selector: (context, settings) => def.reader!(settings) as Enum,
          onSelection: (value) => metaSettingsEngine.apply(def, value),
          tileTitle: def.title,
          dialogTitle: def.dialogTitle?.call(context),
          optionSubtitleBuilder: def.optionSubtitle == null ? null : (value) => def.optionSubtitle!(context, value),
        );
      case SettingWidgetKind.custom:
        return metaEditorRegistry[def.editorKey!]!(context, def);
      case SettingWidgetKind.subPage:
        return MetaSubPageTile(
          title: def.title,
          routeName: def.routeName!,
          builder: metaPageRegistry[def.routeName!]!,
        );
    }
  }
}
