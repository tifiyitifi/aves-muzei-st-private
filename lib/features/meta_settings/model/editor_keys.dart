/// Identifiers for fork-owned custom editors.
///
/// A `SettingDef` with `SettingWidgetKind.custom` references one of these in
/// `editorKey`; the view layer maps it to a widget in the editor registry.
abstract final class MetaEditorKeys {
  static const String settingsEngine = 'settings_engine';
  static const String themeColorMode = 'theme_color_mode';
  static const String forceTvLayout = 'force_tv_layout';
}
