/// How a `SettingDef` is rendered and edited by the generic renderer.
///
/// The renderer switch is exhaustive, so a widget kind exists only once a
/// catalog entry needs it (numeric/slider kinds are added when a numeric
/// setting migrates).
enum SettingWidgetKind {
  /// Boolean setting rendered as a switch.
  toggle,

  /// Enum setting rendered as a single-selection tile.
  enumPick,

  /// Setting whose editor is fork-owned and registered by `editorKey`.
  custom,
}
