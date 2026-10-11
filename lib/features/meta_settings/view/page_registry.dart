import 'package:aves/features/meta_settings/model/page_keys.dart';
import 'package:aves/widgets/settings/navigation/bottom_nav_actions_editor_page.dart';
import 'package:aves/widgets/settings/navigation/confirmation_dialog_page.dart';
import 'package:aves/widgets/settings/navigation/drawer_editor_page.dart';
import 'package:aves/widgets/settings/privacy/access_grants_page.dart';
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
import 'package:flutter/widgets.dart';

/// Maps a `SettingDef.routeName` (`MetaPageKeys`) to the page it pushes.
///
/// Kept in the view layer so the catalog never imports view pages; this is also
/// the single place where complex settings are delegated to existing sub-pages.
final Map<String, WidgetBuilder> metaPageRegistry = {
  MetaPageKeys.hiddenItems: (context) => const HiddenItemsPage(),
  MetaPageKeys.storageAccess: (context) => const StorageAccessPage(),
  MetaPageKeys.permissions: (context) => const PermissionsPage(),
  MetaPageKeys.viewerActions: (context) => const ViewerActionEditorPage(),
  MetaPageKeys.viewerOverlay: (context) => const ViewerOverlayPage(),
  MetaPageKeys.viewerSlideshow: (context) => const ViewerSlideshowPage(),
  MetaPageKeys.videoPlayback: (context) => const VideoPlaybackPage(),
  MetaPageKeys.videoControls: (context) => const VideoControlsPage(),
  MetaPageKeys.subtitleTheme: (context) => const SubtitleThemePage(),
  MetaPageKeys.collectionActions: (context) => const CollectionActionEditorPage(),
  MetaPageKeys.thumbnailOverlay: (context) => const ThumbnailOverlayPage(),
  MetaPageKeys.navigationDrawer: (context) => const NavigationDrawerEditorPage(),
  MetaPageKeys.bottomNavActions: (context) => const BottomNavigationActionEditorPage(),
  MetaPageKeys.confirmationDialog: (context) => const ConfirmationDialogPage(),
};
