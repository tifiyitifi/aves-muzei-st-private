import 'dart:async';

import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_nav_mode.dart';
import 'package:aves/features/grouped_wallpaper/services/grouped_wallpaper_nav_controller.dart';
import 'package:aves/features/grouped_wallpaper/view/grouped_wallpaper_nav.dart';
import 'package:aves/features/grouped_wallpaper/view/grouped_wallpaper_page.dart';
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
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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

/// Destinations the bar adds on its own, shown read-only.
///
/// The displayed-buttons list is the user's own `bottomNavigationActions`, but
/// the bar also appends the visible range and derives the wallpaper entry. This
/// section is what makes the editor describe the bar the user actually sees;
/// adding a destination to the list above turns it into an editable button here
/// as well.
class _DerivedDestinations extends StatelessWidget {
  final QuickActionEditorController<AvesNavItem> controller;

  const new({required this.controller});

  @override
  Widget build(BuildContext context) {
    final mode = context.select<GroupedWallpaperNavController, GroupedWallpaperNavMode>((v) => v.mode);
    final entryClosed = context.select<GroupedWallpaperNavController, bool>((v) => v.entryClosed);
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final derived = derivedNavDestinations(controller.items, mode: mode, entryClosed: entryClosed);
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
