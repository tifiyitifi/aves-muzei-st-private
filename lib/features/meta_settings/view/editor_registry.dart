import 'package:aves/features/collection_paging/view/collection_paging_editors.dart';
import 'package:aves/features/meta_settings/model/editor_keys.dart';
import 'package:aves/features/meta_settings/model/setting_def.dart';
import 'package:aves/features/meta_settings/view/widgets/editors/accessibility_editors.dart';
import 'package:aves/features/meta_settings/view/widgets/editors/display_editors.dart';
import 'package:aves/features/meta_settings/view/widgets/editors/language_editors.dart';
import 'package:aves/features/meta_settings/view/widgets/editors/navigation_editors.dart';
import 'package:aves/features/meta_settings/view/widgets/editors/privacy_editors.dart';
import 'package:aves/features/meta_settings/view/widgets/editors/settings_engine_editor.dart';
import 'package:aves/features/meta_settings/view/widgets/editors/thumbnails_editors.dart';
import 'package:aves/features/meta_settings/view/widgets/editors/video_editors.dart';
import 'package:aves/features/meta_settings/view/widgets/editors/viewer_editors.dart';
import 'package:aves/features/meta_settings/view/widgets/editors/wallpaper_editors.dart';
import 'package:aves/features/wallpaper_lock/model/wallpaper_lock_kind.dart';
import 'package:aves/features/wallpaper_lock/view/widgets/wallpaper_lock_editor.dart';
import 'package:flutter/widgets.dart';

typedef MetaEditorBuilder = Widget Function(BuildContext context, SettingDef def);

/// Maps `SettingDef.editorKey` to a fork-owned editor widget.
final Map<String, MetaEditorBuilder> metaEditorRegistry = {
  MetaEditorKeys.settingsEngine: (context, def) => const SettingsEngineEditor(),
  MetaEditorKeys.themeColorMode: (context, def) => ThemeColorModeEditor(def: def),
  MetaEditorKeys.forceTvLayout: (context, def) => ForceTvLayoutEditor(def: def),
  MetaEditorKeys.locale: (context, def) => LocaleEditor(def: def),
  MetaEditorKeys.timeToTakeAction: (context, def) => TimeToTakeActionEditor(def: def),
  MetaEditorKeys.permissions: (context, def) => PermissionsEditor(def: def),
  MetaEditorKeys.enableBin: (context, def) => EnableBinEditor(def: def),
  MetaEditorKeys.autoExportSettings: (context, def) => AutoExportSettingsEditor(def: def),
  MetaEditorKeys.viewerUseCutout: (context, def) => ViewerUseCutoutEditor(def: def),
  MetaEditorKeys.viewerImageBackground: (context, def) => ViewerImageBackgroundEditor(def: def),
  MetaEditorKeys.videoShowVideos: (context, def) => VideoShowVideosEditor(def: def),
  MetaEditorKeys.videoThumbnailMethods: (context, def) => VideoThumbnailMethodsEditor(def: def),
  MetaEditorKeys.burstPatterns: (context, def) => BurstPatternsEditor(def: def),
  MetaEditorKeys.homePage: (context, def) => HomePageEditor(def: def),
  MetaEditorKeys.collectionEngine: (context, def) => CollectionEngineEditor(def: def),
  MetaEditorKeys.collectionWindowSize: (context, def) => CollectionWindowSizeEditor(def: def),
  MetaEditorKeys.collectionPrefetchScreens: (context, def) => CollectionPrefetchScreensEditor(def: def),
  MetaEditorKeys.collectionThreshold: (context, def) => CollectionThresholdEditor(def: def),
  MetaEditorKeys.collectionAskBeforeCatalog: (context, def) => CollectionAskBeforeCatalogEditor(def: def),
  MetaEditorKeys.collectionBrowseOnlyBar: (context, def) => CollectionBrowseOnlyBarEditor(def: def),
  MetaEditorKeys.collectionBackgroundWork: (context, def) => CollectionBackgroundWorkEditor(def: def),
  MetaEditorKeys.wallpaperNavMode: (context, def) => WallpaperNavModeEditor(def: def),
  MetaEditorKeys.wallpaperNotification: (context, def) => WallpaperNotificationEditor(def: def),
  MetaEditorKeys.wallpaperHistoryLimit: (context, def) => WallpaperHistoryLimitEditor(def: def),
  MetaEditorKeys.wallpaperLockVisibleRange: (context, def) => WallpaperLockEditor(def: def, kind: WallpaperLockKind.visibleRange),
  MetaEditorKeys.wallpaperLockGroupSwitch: (context, def) => WallpaperLockEditor(def: def, kind: WallpaperLockKind.groupSwitch),
};
