import 'dart:async';

import 'package:aves/features/drift_db/app_database_provider.dart';
import 'package:aves/features/grouped_wallpaper/db/wallpaper_group_store.dart';
import 'package:aves/features/grouped_wallpaper/log.dart';
import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_nav_mode.dart';
import 'package:aves/features/grouped_wallpaper/services/grouped_wallpaper_nav_controller.dart';
import 'package:aves/features/grouped_wallpaper/services/wallpaper_engine_link.dart';
import 'package:aves/features/grouped_wallpaper/view/widgets/grouped_wallpaper_history_limit_dialog.dart';
import 'package:aves/features/meta_settings/model/setting_def.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/common/identity/aves_list_subtitle.dart';
import 'package:aves/widgets/dialogs/selection_dialogs/common.dart';
import 'package:aves/widgets/dialogs/selection_dialogs/single_selection.dart';
import 'package:material_ui/material_ui.dart';

/// Editors of the "Visible & wallpaper" category.
///
/// The grouped wallpaper keeps its switches in AppMeta, not in the v1 settings
/// store, so none of them can be a generic `toggle` def: each one reads the
/// store asynchronously and writes it back, and the engine link is told so the
/// frame on screen and the notification follow at once.

Future<WallpaperGroupStore> _store() async => WallpaperGroupStore(await getIt<AppDatabaseProvider>().open());

String _navModeName(BuildContext context, GroupedWallpaperNavMode mode) => switch (mode) {
      GroupedWallpaperNavMode.shared => context.l10n.settingsWallpaperNavModeShared,
      GroupedWallpaperNavMode.separateLeft => context.l10n.settingsWallpaperNavModeLeft,
      GroupedWallpaperNavMode.separateRight => context.l10n.settingsWallpaperNavModeRight,
    };

/// Picks where the wallpaper's bottom-bar entry sits relative to the visible
/// range's.
class WallpaperNavModeEditor extends StatelessWidget {
  final SettingDef def;

  const new({super.key, required this.def});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: groupedWallpaperNavController,
        builder: (context, _) {
          final mode = groupedWallpaperNavController.mode;
          return ListTile(
            title: Text(def.title(context)),
            subtitle: AvesListSubtitle(_navModeName(context, mode)),
            onTap: () => showSelectionDialog<GroupedWallpaperNavMode>(
              context: context,
              builder: (context) => AvesSingleSelectionDialog<GroupedWallpaperNavMode>(
                initialValue: mode,
                options: {for (final value in GroupedWallpaperNavMode.values) value: _navModeName(context, value)},
                title: context.l10n.settingsWallpaperNavMode,
              ),
              onSelection: (value) => unawaited(groupedWallpaperNavController.setMode(value)),
            ),
          );
        },
      );
}

/// A switch whose value lives in the wallpaper's AppMeta.
///
/// The value is read once when the tile is built: the settings page is a list,
/// so a tile is created when it scrolls into view, which is soon enough and
/// keeps a database read off every rebuild.
class _WallpaperSwitchTile extends StatefulWidget {
  final String title;
  final String? subtitle;
  final Future<bool> Function(WallpaperGroupStore store) read;
  final Future<void> Function(WallpaperGroupStore store, bool value) write;

  const new({
    required this.title,
    this.subtitle,
    required this.read,
    required this.write,
  });

  @override
  State<_WallpaperSwitchTile> createState() => _WallpaperSwitchTileState();
}

class _WallpaperSwitchTileState extends State<_WallpaperSwitchTile> {
  bool? _value;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final value = await widget.read(await _store());
      if (!mounted) return;
      setState(() => _value = value);
    } catch (error, stack) {
      groupedWallpaperLog.e('failed to read a wallpaper setting', error, stack);
    }
  }

  Future<void> _set(bool value) async {
    setState(() => _value = value);
    try {
      await widget.write(await _store(), value);
    } catch (error, stack) {
      groupedWallpaperLog.e('failed to write a wallpaper setting', error, stack);
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = _value;
    return SwitchListTile(
      value: value ?? true,
      // Greyed until the stored value is known, so a tap can never write a value
      // the user did not see.
      onChanged: value == null ? null : (v) => unawaited(_set(v)),
      title: Text(widget.title),
      subtitle: widget.subtitle == null ? null : Text(widget.subtitle!),
    );
  }
}

/// The notification-bar switch.
class WallpaperNotificationEditor extends StatelessWidget {
  final SettingDef def;

  const new({super.key, required this.def});

  @override
  Widget build(BuildContext context) => _WallpaperSwitchTile(
        title: def.title(context),
        subtitle: def.subtitle?.call(context),
        read: (store) => store.readNotification(),
        write: (store, value) async {
          await store.writeNotification(value);
          await wallpaperEngineLink.setNotification(value);
        },
      );
}

/// Opens the history limit dialog, the same one the group page and the history
/// page use, so the number is entered one way everywhere.
class WallpaperHistoryLimitEditor extends StatefulWidget {
  final SettingDef def;

  const new({super.key, required this.def});

  @override
  State<WallpaperHistoryLimitEditor> createState() => _WallpaperHistoryLimitEditorState();
}

class _WallpaperHistoryLimitEditorState extends State<WallpaperHistoryLimitEditor> {
  int? _limit;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final limit = await (await _store()).readHistoryLimit();
      if (!mounted) return;
      setState(() => _limit = limit);
    } catch (error, stack) {
      groupedWallpaperLog.e('failed to read the wallpaper history limit', error, stack);
    }
  }

  Future<void> _edit() async {
    final limit = _limit;
    if (limit == null) return;
    final value = await showGroupedWallpaperHistoryLimitDialog(context, limit: limit);
    if (value == null || !mounted) return;
    try {
      // The store is the source of truth; the engine call only carries the value
      // into `state.json` so the notification greys "previous" at once.
      await (await _store()).writeHistoryLimit(value);
      await wallpaperEngineLink.setHistoryLimit(value);
    } catch (error, stack) {
      groupedWallpaperLog.e('failed to write the wallpaper history limit', error, stack);
    }
    if (!mounted) return;
    setState(() => _limit = value);
  }

  @override
  Widget build(BuildContext context) {
    final limit = _limit;
    return ListTile(
      title: Text(widget.def.title(context)),
      subtitle: limit == null ? null : Text('$limit'),
      enabled: limit != null,
      onTap: () => unawaited(_edit()),
    );
  }
}
