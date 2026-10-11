import 'package:aves/features/meta_settings/model/page_keys.dart';
import 'package:aves/widgets/settings/navigation/bottom_nav_actions_editor_page.dart';
import 'package:aves/widgets/settings/navigation/confirmation_dialog_page.dart';
import 'package:aves/widgets/settings/navigation/drawer_editor_page.dart';
import 'package:aves/widgets/settings/privacy/hidden_items_page.dart';
import 'package:aves/widgets/settings/privacy/permissions/permissions_page.dart';
import 'package:aves/widgets/settings/thumbnails/collection_actions_editor_page.dart';
import 'package:aves/widgets/settings/thumbnails/overlay_page.dart';
import 'package:aves/widgets/settings/viewer/overlay_page.dart';
import 'package:aves/widgets/settings/viewer/slideshow_page.dart';
import 'package:aves/widgets/settings/viewer/viewer_actions_editor_page.dart';
import 'package:aves/widgets/settings/video/controls_page.dart';
import 'package:aves/widgets/settings/video/playback_page.dart';
import 'package:aves/widgets/settings/video/subtitle_theme_page.dart';

/// The setting keys of each sub-page, used to match a sub-page entry against
/// `Settings.recentSettingKeys`.
///
/// Upstream `SettingsTile`s expose `settingKeys`, and sub-page tiles delegate to
/// the page's static constant; the catalog's `SettingDef` has no such concept, so
/// this map restores the behaviour without importing pages into the catalog. A
/// page that declares no key (or none editable) maps to an empty list, matching
/// its upstream tile.
const Map<String, List<String>> metaPageSearchKeys = {
  MetaPageKeys.hiddenItems: HiddenItemsPage.settingKeys,
  MetaPageKeys.storageAccess: <String>[], // upstream tile declares no editable setting
  MetaPageKeys.permissions: PermissionsPage.settingKeys,
  MetaPageKeys.viewerActions: ViewerActionEditorPage.settingKeys,
  MetaPageKeys.viewerOverlay: ViewerOverlayPage.settingKeys,
  MetaPageKeys.viewerSlideshow: ViewerSlideshowPage.settingKeys,
  MetaPageKeys.videoPlayback: VideoPlaybackPage.settingKeys,
  MetaPageKeys.videoControls: VideoControlsPage.settingKeys,
  MetaPageKeys.subtitleTheme: SubtitleThemePage.settingKeys,
  MetaPageKeys.collectionActions: CollectionActionEditorPage.settingKeys,
  MetaPageKeys.thumbnailOverlay: ThumbnailOverlayPage.settingKeys,
  MetaPageKeys.navigationDrawer: NavigationDrawerEditorPage.settingKeys,
  MetaPageKeys.bottomNavActions: BottomNavigationActionEditorPage.settingKeys,
  MetaPageKeys.confirmationDialog: ConfirmationDialogPage.settingKeys,
};
