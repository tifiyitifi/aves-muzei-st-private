import 'package:aves/features/meta_settings/data/def_visibility.dart';
import 'package:aves/features/meta_settings/model/editor_keys.dart';
import 'package:aves/features/meta_settings/model/enum/setting_widget_kind.dart';
import 'package:aves/features/meta_settings/model/enum/settings_category.dart';
import 'package:aves/features/meta_settings/model/setting_def.dart';
import 'package:aves/features/meta_settings/store/settings_engine_gate.dart';
import 'package:aves/view/view.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves_model/aves_model.dart';

/// The declarative catalog driving the metadata settings surface (v2).
///
/// Sections migrate whole, one category at a time: a category's defs are added
/// here when its legacy section is ported. Categories absent from the catalog
/// fall back to a fork-owned copy of the legacy section.
final List<SettingDef> metaSettingsCatalog = [
  ..._displayDefs,
  ..._advancedDefs,
];

/// Defs of [category], ordered by `sortOrder`.
List<SettingDef> metaSettingsDefsFor(SettingsCategory category) =>
    metaSettingsCatalog.where((def) => def.category == category).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

// Display

final List<SettingDef> _displayDefs = [
  SettingDef(
    key: SettingKeys.themeBrightnessKey,
    category: SettingsCategory.display,
    widgetKind: SettingWidgetKind.enumPick,
    title: (context) => context.l10n.settingsThemeBrightnessTile,
    reader: (settings) => settings.themeBrightness,
    enumValues: AvesThemeBrightness.values,
    enumName: (context, value) => (value as AvesThemeBrightness).getName(context),
    dialogTitle: (context) => context.l10n.settingsThemeBrightnessDialogTitle,
    availabilityKey: DefVisibility.notTv,
    sortOrder: 10,
  ),
  SettingDef(
    key: SettingKeys.themeColorModeKey,
    category: SettingsCategory.display,
    widgetKind: SettingWidgetKind.custom,
    title: (context) => context.l10n.settingsThemeColorHighlights,
    editorKey: MetaEditorKeys.themeColorMode,
    sortOrder: 20,
  ),
  SettingDef(
    key: SettingKeys.enableDynamicColorKey,
    category: SettingsCategory.display,
    widgetKind: SettingWidgetKind.toggle,
    title: (context) => context.l10n.settingsThemeEnableDynamicColor,
    reader: (settings) => settings.enableDynamicColor,
    availabilityKey: DefVisibility.dynamicColor,
    sortOrder: 30,
  ),
  SettingDef(
    key: SettingKeys.enableBlurEffectKey,
    category: SettingsCategory.display,
    widgetKind: SettingWidgetKind.toggle,
    title: (context) => context.l10n.settingsViewerEnableOverlayBlurEffect,
    reader: (settings) => settings.enableBlurEffect,
    sortOrder: 40,
  ),
  SettingDef(
    key: SettingKeys.maxBrightnessKey,
    category: SettingsCategory.display,
    widgetKind: SettingWidgetKind.enumPick,
    title: (context) => context.l10n.settingsViewerMaximumBrightness,
    reader: (settings) => settings.maxBrightness,
    enumValues: MaxBrightness.values,
    enumName: (context, value) => (value as MaxBrightness).getName(context),
    availabilityKey: DefVisibility.notTv,
    sortOrder: 50,
  ),
  SettingDef(
    key: SettingKeys.displayRefreshRateModeKey,
    category: SettingsCategory.display,
    widgetKind: SettingWidgetKind.enumPick,
    title: (context) => context.l10n.settingsDisplayRefreshRateModeTile,
    reader: (settings) => settings.displayRefreshRateMode,
    enumValues: DisplayRefreshRateMode.values,
    enumName: (context, value) => (value as DisplayRefreshRateMode).getName(context),
    dialogTitle: (context) => context.l10n.settingsDisplayRefreshRateModeDialogTitle,
    availabilityKey: DefVisibility.notTv,
    sortOrder: 60,
  ),
  SettingDef(
    key: SettingKeys.forceTvLayoutKey,
    category: SettingsCategory.display,
    widgetKind: SettingWidgetKind.custom,
    title: (context) => context.l10n.settingsDisplayUseTvInterface,
    editorKey: MetaEditorKeys.forceTvLayout,
    availabilityKey: DefVisibility.notTelevision,
    sortOrder: 70,
  ),
];

// Advanced

final List<SettingDef> _advancedDefs = [
  SettingDef(
    key: SettingsEngineGate.key,
    category: SettingsCategory.advanced,
    widgetKind: SettingWidgetKind.custom,
    title: (context) => context.l10n.settingsEngineTile,
    editorKey: MetaEditorKeys.settingsEngine,
    sortOrder: 10,
  ),
];
