import 'package:aves/features/meta_settings/data/catalog.dart';
import 'package:aves/features/meta_settings/model/enum/setting_widget_kind.dart';
import 'package:aves/features/meta_settings/model/page_keys.dart';
import 'package:aves/features/meta_settings/view/page_registry.dart';
import 'package:aves/features/meta_settings/view/page_search_keys.dart';
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
import 'package:flutter_test/flutter_test.dart';

/// The search-key map must stay in sync with the catalog's sub-page defs and
/// with the upstream pages' static `settingKeys` (the recent-settings fix).
void main() {
  test('every sub-page def has a search-key entry', () {
    final subPageDefs = metaSettingsCatalog.where((def) => def.widgetKind == SettingWidgetKind.subPage);
    expect(subPageDefs, isNotEmpty);
    for (final def in subPageDefs) {
      expect(metaPageSearchKeys.containsKey(def.routeName), isTrue, reason: 'missing search keys for ${def.routeName}');
    }
  });

  test('search keys cover exactly the registered sub-pages', () {
    expect(metaPageSearchKeys.keys.toSet(), metaPageRegistry.keys.toSet());
  });

  test('search keys mirror the upstream page constants', () {
    expect(metaPageSearchKeys[MetaPageKeys.hiddenItems], HiddenItemsPage.settingKeys);
    expect(metaPageSearchKeys[MetaPageKeys.permissions], PermissionsPage.settingKeys);
    expect(metaPageSearchKeys[MetaPageKeys.viewerActions], ViewerActionEditorPage.settingKeys);
    expect(metaPageSearchKeys[MetaPageKeys.viewerOverlay], ViewerOverlayPage.settingKeys);
    expect(metaPageSearchKeys[MetaPageKeys.viewerSlideshow], ViewerSlideshowPage.settingKeys);
    expect(metaPageSearchKeys[MetaPageKeys.videoPlayback], VideoPlaybackPage.settingKeys);
    expect(metaPageSearchKeys[MetaPageKeys.videoControls], VideoControlsPage.settingKeys);
    expect(metaPageSearchKeys[MetaPageKeys.subtitleTheme], SubtitleThemePage.settingKeys);
    expect(metaPageSearchKeys[MetaPageKeys.collectionActions], CollectionActionEditorPage.settingKeys);
    expect(metaPageSearchKeys[MetaPageKeys.thumbnailOverlay], ThumbnailOverlayPage.settingKeys);
    expect(metaPageSearchKeys[MetaPageKeys.navigationDrawer], NavigationDrawerEditorPage.settingKeys);
    expect(metaPageSearchKeys[MetaPageKeys.bottomNavActions], BottomNavigationActionEditorPage.settingKeys);
    expect(metaPageSearchKeys[MetaPageKeys.confirmationDialog], ConfirmationDialogPage.settingKeys);
    // the storage-access page declares no editable setting upstream
    expect(metaPageSearchKeys[MetaPageKeys.storageAccess], isEmpty);
  });
}
