import 'package:aves/features/meta_settings/model/enum/setting_widget_kind.dart';
import 'package:aves/features/meta_settings/model/enum/settings_category.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:flutter/widgets.dart';

/// One declarative entry of the metadata settings catalog.
///
/// The renderer is generic: a def declares how to *read* its current value
/// ([reader]) and how to *edit* it ([widgetKind] plus [enumValues] or
/// [editorKey]). Writes go through `SettingsAccess.set(key, value)`, so a def
/// never needs a typed setter and [reader] reuses the app's typed getters —
/// keeping each default in exactly one place instead of duplicating
/// `SettingsDefaults` here.
class SettingDef {
  /// `SettingKeys` constant identifying the setting. Referencing the constant
  /// (not a literal) makes a typo a compile error.
  final String key;

  final SettingsCategory category;

  final SettingWidgetKind widgetKind;

  /// Localized title. The generated `context.l10n.<key>` getter is
  /// compile-checked, so no ARB-key indirection is needed.
  final String Function(BuildContext context) title;

  /// Current value, with the app default applied. Required unless [widgetKind]
  /// is [SettingWidgetKind.custom].
  final Object? Function(Settings settings)? reader;

  /// Typed writer for settings whose setter has internal side effects (e.g.
  /// `calendar` resets the cached locale). When present the engine calls it
  /// instead of the generic `SettingsAccess.set`, and [reader] must return the
  /// value type it accepts.
  final void Function(Settings settings, Object? value)? mutator;

  final String Function(BuildContext context)? subtitle;

  /// Candidate values for [SettingWidgetKind.enumPick].
  final List<Enum>? enumValues;

  /// Localized name of an [enumValues] member for [SettingWidgetKind.enumPick].
  final String Function(BuildContext context, Enum value)? enumName;

  /// Dialog title for [SettingWidgetKind.enumPick]; defaults to [title].
  final String Function(BuildContext context)? dialogTitle;

  /// Option subtitle for [SettingWidgetKind.enumPick], e.g. a sample rendering.
  final String? Function(BuildContext context, Enum value)? optionSubtitle;

  /// Route name for [SettingWidgetKind.subPage]. The view resolves the page from
  /// `metaPageRegistry`, so the catalog stays free of view imports.
  final String? routeName;

  /// Registered editor for [SettingWidgetKind.custom] (see `MetaEditorKeys`).
  final String? editorKey;

  /// Registered runtime predicate gating visibility (see `DefVisibility`).
  final String? availabilityKey;

  /// Within-category order; lower comes first.
  final int sortOrder;

  const new({
    required this.key,
    required this.category,
    required this.widgetKind,
    required this.title,
    this.reader,
    this.mutator,
    this.subtitle,
    this.enumValues,
    this.enumName,
    this.dialogTitle,
    this.optionSubtitle,
    this.routeName,
    this.editorKey,
    this.availabilityKey,
    this.sortOrder = 0,
  });
}
