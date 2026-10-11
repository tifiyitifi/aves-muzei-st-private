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
import 'package:flutter_test/flutter_test.dart';

/// `MetaPageKeys` values must match the pages they resolve to, or the
/// `RouteSettings` name pushed for a sub-page would be wrong.
void main() {
  test('page keys mirror the upstream route names', () {
    expect(MetaPageKeys.hiddenItems, HiddenItemsPage.routeName);
    expect(MetaPageKeys.storageAccess, StorageAccessPage.routeName);
    expect(MetaPageKeys.permissions, PermissionsPage.routeName);
    expect(MetaPageKeys.viewerActions, ViewerActionEditorPage.routeName);
    expect(MetaPageKeys.viewerOverlay, ViewerOverlayPage.routeName);
    expect(MetaPageKeys.viewerSlideshow, ViewerSlideshowPage.routeName);
    expect(MetaPageKeys.videoPlayback, VideoPlaybackPage.routeName);
    expect(MetaPageKeys.videoControls, VideoControlsPage.routeName);
    expect(MetaPageKeys.subtitleTheme, SubtitleThemePage.routeName);
    expect(MetaPageKeys.collectionActions, CollectionActionEditorPage.routeName);
    expect(MetaPageKeys.thumbnailOverlay, ThumbnailOverlayPage.routeName);
    expect(MetaPageKeys.navigationDrawer, NavigationDrawerEditorPage.routeName);
    expect(MetaPageKeys.bottomNavActions, BottomNavigationActionEditorPage.routeName);
    expect(MetaPageKeys.confirmationDialog, ConfirmationDialogPage.routeName);
  });
}
