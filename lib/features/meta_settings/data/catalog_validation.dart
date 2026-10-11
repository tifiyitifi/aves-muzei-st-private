import 'package:aves/features/meta_settings/model/enum/setting_widget_kind.dart';
import 'package:aves/features/meta_settings/model/setting_def.dart';

/// Structural checks for the catalog, run in debug and pinned by tests.
///
/// Key and title correctness is already guaranteed at compile time (defs
/// reference `SettingKeys` constants and generated `context.l10n` getters), so
/// this checks only what the compiler cannot: uniqueness and per-widget-kind
/// completeness.
List<String> validateMetaSettingsCatalog(
  Iterable<SettingDef> defs, {
  required Set<String> registeredEditorKeys,
  required Set<String> registeredAvailabilityKeys,
  required Set<String> registeredPageRouteNames,
}) {
  final problems = <String>[];
  final seenKeys = <String>{};

  for (final def in defs) {
    if (!seenKeys.add(def.key)) {
      problems.add('duplicate key "${def.key}"');
    }

    switch (def.widgetKind) {
      case SettingWidgetKind.toggle:
        if (def.reader == null) problems.add('${def.key}: toggle needs a reader');
      case SettingWidgetKind.enumPick:
        if (def.reader == null) problems.add('${def.key}: enumPick needs a reader');
        if (def.enumValues == null || def.enumValues!.isEmpty) problems.add('${def.key}: enumPick needs enumValues');
        if (def.enumName == null) problems.add('${def.key}: enumPick needs enumName');
      case SettingWidgetKind.custom:
        final editorKey = def.editorKey;
        if (editorKey == null) {
          problems.add('${def.key}: custom needs an editorKey');
        } else if (!registeredEditorKeys.contains(editorKey)) {
          problems.add('${def.key}: unregistered editorKey "$editorKey"');
        }
      case SettingWidgetKind.subPage:
        final routeName = def.routeName;
        if (routeName == null) {
          problems.add('${def.key}: subPage needs a routeName');
        } else if (!registeredPageRouteNames.contains(routeName)) {
          problems.add('${def.key}: unregistered sub-page "$routeName"');
        }
    }

    final availabilityKey = def.availabilityKey;
    if (availabilityKey != null && !registeredAvailabilityKeys.contains(availabilityKey)) {
      problems.add('${def.key}: unregistered availabilityKey "$availabilityKey"');
    }
  }

  return problems;
}
