import 'dart:async';

import 'package:aves/features/drift_db/app_database_provider.dart';
import 'package:aves/features/grouped_wallpaper/db/wallpaper_group_store.dart';
import 'package:aves/features/grouped_wallpaper/log.dart';
import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_artwork_open_target.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_group.dart';
import 'package:aves/features/grouped_wallpaper/services/wallpaper_engine_link.dart';
import 'package:aves/features/grouped_wallpaper/services/wallpaper_group_controller.dart';
import 'package:aves/features/grouped_wallpaper/view/grouped_wallpaper_auto_advance_page.dart';
import 'package:aves/features/grouped_wallpaper/view/grouped_wallpaper_effects_page.dart';
import 'package:aves/features/grouped_wallpaper/view/grouped_wallpaper_gestures_page.dart';
import 'package:aves/features/grouped_wallpaper/view/grouped_wallpaper_pad_editor_page.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/basic/scaffold.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:collection/collection.dart';
import 'package:material_ui/material_ui.dart';

/// Low-frequency settings for the grouped wallpaper's immersive view.
///
/// The page composes the existing editors instead of duplicating them: group
/// settings are bound to the group on screen, while the title destination,
/// notification, gestures and control pad belong to the view as a whole.
class GroupedWallpaperSettingsPage extends StatefulWidget {
  static const routeName = '/wallpaper_groups/settings';

  /// The group whose auto-advance and effects are edited. Group 0 has none.
  final String? groupId;

  /// Optional injected aggregate for tests; production uses the shared controller.
  final WallpaperGroupController? controller;

  const new({super.key, this.groupId, this.controller});

  @override
  State<GroupedWallpaperSettingsPage> createState() => _GroupedWallpaperSettingsPageState();
}

class _GroupedWallpaperSettingsPageState extends State<GroupedWallpaperSettingsPage> {
  WallpaperGroupController get _controller => widget.controller ?? wallpaperGroupController;

  WallpaperGroupStore? _store;
  GroupedWallpaperArtworkOpenTarget? _artworkOpenTarget;
  bool? _notification;
  bool _controllerReady = false;

  WallpaperGroup? get _group {
    final groupId = widget.groupId;
    if (!_controllerReady || groupId == null || groupId.isEmpty || groupId == wallpaperGroupNoneId) return null;
    return _controller.groups.firstWhereOrNull((candidate) => candidate.id == groupId);
  }

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    WallpaperGroupStore? store;
    GroupedWallpaperArtworkOpenTarget? artworkOpenTarget;
    bool? notification;
    try {
      store = WallpaperGroupStore(await getIt<AppDatabaseProvider>().open());
      artworkOpenTarget = await store.readViewArtworkOpenTarget();
      notification = await store.readNotification();
    } catch (error, stack) {
      groupedWallpaperLog.e('failed to read the grouped wallpaper view settings', error, stack);
    }

    var controllerReady = false;
    try {
      // A gesture can cold-start the app, so the group list may not be loaded.
      final groupId = widget.groupId;
      if (groupId != null && groupId.isNotEmpty && groupId != wallpaperGroupNoneId) {
        await _controller.init();
        controllerReady = true;
      }
    } catch (error, stack) {
      groupedWallpaperLog.e('failed to load the viewed wallpaper group', error, stack);
    }

    if (!mounted) return;
    setState(() {
      _store = store;
      _artworkOpenTarget = artworkOpenTarget;
      _notification = notification;
      _controllerReady = controllerReady;
    });
  }

  Future<void> _setArtworkOpenTarget(GroupedWallpaperArtworkOpenTarget target) async {
    setState(() => _artworkOpenTarget = target);
    final store = _store;
    if (store == null) return;
    try {
      await store.writeViewArtworkOpenTarget(target);
    } catch (error, stack) {
      groupedWallpaperLog.e('failed to write the artwork title destination', error, stack);
    }
  }

  Future<void> _pickArtworkOpenTarget(GroupedWallpaperArtworkOpenTarget current) async {
    final selected = await showDialog<GroupedWallpaperArtworkOpenTarget>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.groupedWallpaperSettingsArtworkTap),
        content: SingleChildScrollView(
          child: RadioGroup<GroupedWallpaperArtworkOpenTarget>(
            groupValue: current,
            onChanged: (target) => Navigator.of(context).pop(target),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final target in GroupedWallpaperArtworkOpenTarget.values)
                  RadioListTile<GroupedWallpaperArtworkOpenTarget>(
                    value: target,
                    title: Text(_artworkTargetName(context, target)),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(MaterialLocalizations.of(context).cancelButtonLabel)),
        ],
      ),
    );
    if (selected != null) await _setArtworkOpenTarget(selected);
  }

  Future<void> _setNotification(bool enabled) async {
    setState(() => _notification = enabled);
    final store = _store;
    if (store == null) return;
    try {
      await store.writeNotification(enabled);
      await wallpaperEngineLink.setNotification(enabled);
      if (!mounted || enabled) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.wallpaperNotificationOffHint)));
    } catch (error, stack) {
      groupedWallpaperLog.e('failed to write the wallpaper notification setting', error, stack);
    }
  }

  Future<void> _openAutoAdvance() async {
    final group = _group;
    if (group == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: GroupedWallpaperAutoAdvancePage.routeName),
        builder: (_) => GroupedWallpaperAutoAdvancePage(groupId: group.id, controller: _controller),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openEffects() async {
    final group = _group;
    if (group == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: GroupedWallpaperEffectsPage.routeName),
        builder: (_) => GroupedWallpaperEffectsPage(groupId: group.id, controller: _controller),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openGestures() => Navigator.of(context).push(
    MaterialPageRoute(
      settings: const RouteSettings(name: GroupedWallpaperGesturesPage.routeName),
      builder: (_) => const GroupedWallpaperGesturesPage(),
    ),
  );

  Future<void> _openPadEditor() => Navigator.of(context).push(
    MaterialPageRoute(
      settings: const RouteSettings(name: GroupedWallpaperPadEditorPage.routeName),
      builder: (_) => const GroupedWallpaperPadEditorPage(),
    ),
  );

  String _artworkTargetName(BuildContext context, GroupedWallpaperArtworkOpenTarget target) {
    final l10n = context.l10n;
    return switch (target) {
      GroupedWallpaperArtworkOpenTarget.viewer => l10n.groupedWallpaperViewOpenInViewer,
      GroupedWallpaperArtworkOpenTarget.album => l10n.groupedWallpaperViewOpenInAlbum,
      GroupedWallpaperArtworkOpenTarget.group => l10n.groupedWallpaperViewWholeGroup,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final artworkOpenTarget = _artworkOpenTarget;
    final notification = _notification;
    return AvesScaffold(
      appBar: AppBar(title: Text(l10n.groupedWallpaperSettingsTitle)),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final group = _group;
          return ListView(
            children: [
              ListTile(
                leading: const Icon(AIcons.image),
                title: Text(l10n.groupedWallpaperSettingsArtworkTap),
                subtitle: artworkOpenTarget == null ? null : Text(_artworkTargetName(context, artworkOpenTarget)),
                enabled: artworkOpenTarget != null,
                onTap: artworkOpenTarget == null ? null : () => unawaited(_pickArtworkOpenTarget(artworkOpenTarget)),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(AIcons.autoAdvance),
                title: Text(l10n.muzeiWallpaperAutoAdvance),
                subtitle: group == null ? null : Text(groupedWallpaperAutoAdvanceSummary(context, group)),
                trailing: const Icon(AIcons.next),
                enabled: group != null,
                onTap: group == null ? null : () => unawaited(_openAutoAdvance()),
              ),
              ListTile(
                leading: const Icon(AIcons.palette),
                title: Text(l10n.muzeiWallpaperEffects),
                trailing: const Icon(AIcons.next),
                enabled: group != null,
                onTap: group == null ? null : () => unawaited(_openEffects()),
              ),
              const Divider(height: 1),
              SwitchListTile(
                secondary: const Icon(AIcons.checked),
                title: Text(l10n.wallpaperGroupNotification),
                value: notification ?? true,
                // Greyed until the stored value is known, so a tap cannot write a
                // value the user did not see.
                onChanged: notification == null ? null : (value) => unawaited(_setNotification(value)),
              ),
              ListTile(
                leading: const Icon(AIcons.gestures),
                title: Text(l10n.wallpaperGroupGestures),
                trailing: const Icon(AIcons.next),
                onTap: () => unawaited(_openGestures()),
              ),
              ListTile(
                leading: const Icon(AIcons.dragHandle),
                title: Text(l10n.settingsWallpaperViewPad),
                subtitle: Text(l10n.settingsWallpaperViewPadSubtitle),
                trailing: const Icon(AIcons.next),
                onTap: () => unawaited(_openPadEditor()),
              ),
            ],
          );
        },
      ),
    );
  }
}
