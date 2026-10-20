/// Identifiers for fork-owned custom editors.
///
/// A `SettingDef` with `SettingWidgetKind.custom` references one of these in
/// `editorKey`; the view layer maps it to a widget in the editor registry.
abstract final class MetaEditorKeys {
  static const String settingsEngine = 'settings_engine';
  static const String themeColorMode = 'theme_color_mode';
  static const String forceTvLayout = 'force_tv_layout';
  static const String locale = 'locale';
  static const String timeToTakeAction = 'time_to_take_action';
  static const String permissions = 'permissions';
  static const String enableBin = 'enable_bin';
  static const String autoExportSettings = 'auto_export_settings';
  static const String viewerUseCutout = 'viewer_use_cutout';
  static const String viewerImageBackground = 'viewer_image_background';
  static const String videoShowVideos = 'video_show_videos';
  static const String videoThumbnailMethods = 'video_thumbnail_methods';
  static const String burstPatterns = 'burst_patterns';
  static const String homePage = 'home_page';
  static const String collectionEngine = 'collection_engine';
  static const String collectionWindowSize = 'collection_window_size';
  static const String collectionPrefetchScreens = 'collection_prefetch_screens';
  static const String collectionThreshold = 'collection_threshold';
  static const String collectionAskBeforeCatalog = 'collection_ask_before_catalog';
  static const String collectionBackgroundWork = 'collection_background_work';
}
