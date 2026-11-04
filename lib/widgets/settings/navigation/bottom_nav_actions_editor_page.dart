import 'dart:async';

import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_nav_mode.dart';
import 'package:aves/features/grouped_wallpaper/services/grouped_wallpaper_nav_controller.dart';
import 'package:aves/features/grouped_wallpaper/services/grouped_wallpaper_session.dart';
import 'package:aves/features/grouped_wallpaper/view/grouped_wallpaper_nav.dart';
import 'package:aves/features/grouped_wallpaper/view/grouped_wallpaper_page.dart';
import 'package:aves/features/visible_range/view/visible_range_destination.dart';
import 'package:aves/features/visible_range/view/visible_range_page.dart';
import 'package:aves/model/settings/enums/accessibility_animations.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/theme/styles.dart';
import 'package:aves/widgets/collection/collection_page.dart';
import 'package:aves/widgets/common/basic/font_size_icon_theme.dart';
import 'package:aves/widgets/common/basic/popup/menu_row.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/dialogs/pick_dialogs/album_pick_page.dart';
import 'package:aves/widgets/dialogs/pick_dialogs/tag_pick_page.dart';
import 'package:aves/widgets/filter_grids/common/enums.dart';
import 'package:aves/widgets/home/home_page.dart';
import 'package:aves/widgets/navigation/nav_item.dart';
import 'package:aves/widgets/settings/common/quick_actions/editor_page.dart';
import 'package:aves/widgets/settings/navigation/drawer_editor_page.dart';
import 'package:aves/widgets/settings/settings_page.dart';
import 'package:aves_model/aves_model.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

class BottomNavigationActionEditorPage extends StatefulWidget {
  static const routeName = '/settings/navigation/bottom_actions';

  static const List<String> settingKeys = [SettingKeys.bottomNavigationActionsKey];

  const new({super.key});

  @override
  State<BottomNavigationActionEditorPage> createState() => _BottomNavigationActionEditorPageState();
}

class _BottomNavigationActionEditorPageState extends State<BottomNavigationActionEditorPage> {
  late final QuickActionEditorController<AvesNavItem> _controller;

  /// Whether the user's own list had the wallpaper entry before the last edit.
  ///
  /// Removing a *pinned* entry is closing the page: the bar would otherwise
  /// derive it right back from the still-open session, and the user's delete
  /// would look ignored.
  bool _hadWallpaperEntry = false;

  static final allAvailableActions = [
    _collectionActions(),
    _pageActions(),
  ];

  /// The collection destinations, then the two fork pages.
  ///
  /// The visible range and the wallpaper groups are real destinations the bar
  /// derives on its own, so they sit right after the four built-in filters where
  /// a user looks for them. Adding one pins it in the user's own list, which is
  /// also what stops the bar from deriving a second entry.
  static List<AvesNavItem> _collectionActions() {
    final items = NavigationDrawerEditorPage.collectionFilterOptions.map((filter) {
      return AvesNavItem(
        route: CollectionPage.routeName,
        filters: filter != null ? {filter} : null,
      );
    }).toList();
    const forkPages = [
      AvesNavItem(route: VisibleRangePage.routeName),
      AvesNavItem(route: GroupedWallpaperPage.routeName),
    ];
    // The four built-in entries are all/recent/trash/favourites; the media type
    // filters follow them.
    return [...items.take(4), ...forkPages, ...items.skip(4)];
  }

  static List<AvesNavItem> _pageActions() {
    return [
      HomePage.routeName,
      SettingsPage.routeName,
      ...NavigationDrawerEditorPage.pageOptions,
    ].map((v) {
      return AvesNavItem(
        route: v,
      );
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _controller = QuickActionEditorController(
      load: () => settings.bottomNavigationActions,
      save: (actions) => settings.bottomNavigationActions = actions,
    );
    _hadWallpaperEntry = settings.bottomNavigationActions.any(_isWallpaperEntry);
    _controller.addListener(_onItemsChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onItemsChanged);
    _controller.dispose();
    super.dispose();
  }

  static bool _isWallpaperEntry(AvesNavItem item) => item.route == GroupedWallpaperPage.routeName;

  /// Closes the page when its pinned entry is deleted from the list above.
  ///
  /// The working list is what the user is editing, so the close happens at the
  /// moment of the delete instead of waiting for the editor to save on leaving.
  void _onItemsChanged() {
    final has = _controller.items.any(_isWallpaperEntry);
    if (_hadWallpaperEntry && !has) _closeWallpaperPage();
    _hadWallpaperEntry = has;
  }

  @override
  Widget build(BuildContext context) {
    return QuickActionEditorPage<AvesNavItem>(
      title: context.l10n.settingsNavigationBottomActionEditorPageTitle,
      appBarActions: _buildActions(context),
      bannerText: context.l10n.settingsNavigationBottomActionEditorBanner,
      allAvailableActions: allAvailableActions,
      actionIcon: (context, action) => action.getIcon(context),
      actionText: (context, action) => action.getText(context),
      controller: _controller,
      footer: _DerivedDestinations(controller: _controller),
    );
  }

  List<Widget> _buildActions(BuildContext context) {
    final animations = context.select<Settings, AccessibilityAnimations>((v) => v.accessibilityAnimations);
    return [
      PopupMenuButton<_EditorAction>(
        itemBuilder: (context) {
          return [
            _EditorAction.addAlbum,
            _EditorAction.addTag,
          ].map<PopupMenuEntry<_EditorAction>>((v) {
            return PopupMenuItem(
              value: v,
              child: MenuRow(text: v.getText(context), icon: v.getIcon()),
            );
          }).toList();
        },
        onSelected: (action) async {
          // wait for the popup menu to hide before proceeding with the action
          await Future.delayed(animations.popUpAnimationDelay * timeDilation);
          await _onActionSelected(context, action);
        },
        popUpAnimationStyle: animations.popUpAnimationStyle,
      ),
    ].map((v) => FontSizeIconTheme(child: v)).toList();
  }

  Future<void> _onActionSelected(BuildContext context, _EditorAction action) async {
    switch (action) {
      case .addAlbum:
        final albumFilter = await pickAlbum(
          context: context,
          moveType: null,
          chipTypes: AlbumChipType.values.toSet(),
          initialGroup: null,
        );
        if (albumFilter == null) return;
        _controller.add(AvesNavItem(route: CollectionPage.routeName, filters: {albumFilter}));
      case .addTag:
        final tagFilter = await pickTag(
          context: context,
          chipTypes: ChipType.values.toSet(),
          initialGroup: null,
        );
        if (tagFilter == null) return;
        _controller.add(AvesNavItem(route: CollectionPage.routeName, filters: {tagFilter}));
    }
  }
}

enum _EditorAction {
  addAlbum,
  addTag,
}

/// Ends the wallpaper page from the navigation settings, like its own action.
///
/// In the shared mode one entry hosts both pages, so closing flips it back to the
/// range page; a separate entry simply disappears with the session.
void _closeWallpaperPage() {
  closeGroupedWallpaperSession();
  if (groupedWallpaperNavController.mode == GroupedWallpaperNavMode.shared) {
    visibleRangeDestination.value = VisibleRangeDestination.range;
  }
}

/// Destinations the bar adds on its own, shown read-only.
///
/// The displayed-buttons list is the user's own `bottomNavigationActions`, but
/// the bar also appends the visible range and, while its session is open, the
/// wallpaper page. This section is what makes the editor describe the bar the
/// user actually sees; adding a destination to the list above turns it into an
/// editable button here as well.
///
/// The wallpaper entry is the exception: it exists because its session is open,
/// so removing it here is the same close as the page's own action. That is the
/// only way to end the session without opening the page.
class _DerivedDestinations extends StatelessWidget {
  final QuickActionEditorController<AvesNavItem> controller;

  const new({required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([controller, groupedWallpaperNavController]),
      builder: (context, _) {
        final nav = groupedWallpaperNavController;
        final derived = derivedNavDestinations(controller.items, mode: nav.mode, sessionActive: nav.sessionActive);
        if (derived.isEmpty) return const SizedBox();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 16, right: 16),
              child: Text(
                context.l10n.settingsNavigationBottomActionDerivedTitle,
                style: AStyles.sectionTitleStyle(context.knownLocale),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final item in derived)
                    Chip(
                      avatar: item.getIcon(context),
                      label: Text(item.getText(context)),
                      // Only the wallpaper entry is a session: deleting it closes
                      // the page (entry and browsing scope) from here.
                      onDeleted: item.route == GroupedWallpaperPage.routeName ? _closeWallpaperPage : null,
                      deleteButtonTooltipMessage: item.route == GroupedWallpaperPage.routeName ? context.l10n.wallpaperGroupClosePage : null,
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                context.l10n.settingsNavigationBottomActionDerivedHint,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        );
      },
    );
  }
}

extension _ExtraEditorActionView on _EditorAction {
  String getText(BuildContext context) {
    final l10n = context.l10n;
    return switch (this) {
      _EditorAction.addAlbum => l10n.settingsNavigationDrawerAddAlbum,
      _EditorAction.addTag => l10n.tagEditorPageAddTagTooltip,
    };
  }

  Widget getIcon() => Icon(_getIconData());

  IconData _getIconData() {
    return switch (this) {
      _EditorAction.addAlbum => AIcons.album,
      _EditorAction.addTag => AIcons.tag,
    };
  }
}
