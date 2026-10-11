/// Identifiers for sub-page entries (`SettingDef.routeName`).
///
/// Values mirror the upstream pages' route names; `metaPageRegistry` maps them
/// to the pages, and a test keeps the two in sync. Declaring them here keeps the
/// catalog free of view imports.
abstract final class MetaPageKeys {
  static const String hiddenItems = '/settings/hidden_items';
  static const String storageAccess = '/settings/storage_access';
  static const String permissions = '/settings/privacy/permissions';
  static const String viewerActions = '/settings/viewer/actions';
  static const String viewerOverlay = '/settings/viewer/overlay';
  static const String viewerSlideshow = '/settings/viewer/slideshow';
  static const String videoPlayback = '/settings/video/playback';
  static const String videoControls = '/settings/video/controls';
  static const String subtitleTheme = '/settings/video/subtitle_theme';
  static const String collectionActions = '/settings/collection_actions';
  static const String thumbnailOverlay = '/settings/thumbnail_overlay';
  static const String navigationDrawer = '/settings/navigation/drawer';
  static const String bottomNavActions = '/settings/navigation/bottom_actions';
  static const String confirmationDialog = '/settings/navigation_confirmation';
}
