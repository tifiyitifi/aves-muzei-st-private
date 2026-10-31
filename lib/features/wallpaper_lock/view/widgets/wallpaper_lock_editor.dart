import 'dart:async';

import 'package:aves/features/meta_settings/model/setting_def.dart';
import 'package:aves/features/visible_range/services/visible_range_controller.dart';
import 'package:aves/features/wallpaper_lock/model/wallpaper_lock_kind.dart';
import 'package:aves/features/wallpaper_lock/services/wallpaper_lock_service.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/common/identity/aves_list_subtitle.dart';
import 'package:aves/widgets/dialogs/aves_dialog.dart';
import 'package:aves/widgets/dialogs/filter_editors/pin_dialog.dart';
import 'package:material_ui/material_ui.dart';

/// One settings row per lock: state, and the sheet that changes it.
///
/// The row follows the state that actually guards the action, not a copy: the
/// visible range's own `locked` column, and the group switch flag in this
/// service. Locking needs no PIN; unlocking, and changing a PIN, do. This page
/// manages the locks' passwords; the locks themselves are also reachable where
/// they matter (the range padlock and the wallpaper page's menu).
class WallpaperLockEditor extends StatelessWidget {
  final SettingDef def;

  final WallpaperLockKind kind;

  const new({super.key, required this.def, required this.kind});

  bool get _isRangeLock => kind == WallpaperLockKind.visibleRange;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([wallpaperLockService, visibleRangeController]),
        builder: (context, _) {
          final locked = _isRangeLock ? visibleRangeController.gallery.locked : wallpaperLockService.groupSwitchLocked;
          final l10n = context.l10n;
          return ListTile(
            title: Text(def.title(context)),
            subtitle: AvesListSubtitle(locked ? l10n.wallpaperLockSubtitleLocked : l10n.wallpaperLockSubtitleUnlocked),
            trailing: Icon(locked ? AIcons.locked : AIcons.unlocked, size: 20),
            onTap: () => unawaited(_openSheet(context)),
          );
        },
      );

  Future<void> _openSheet(BuildContext context) async {
    final locked = _isRangeLock ? visibleRangeController.gallery.locked : wallpaperLockService.groupSwitchLocked;
    final action = await showModalBottomSheet<_LockAction>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final l10n = sheetContext.l10n;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(l10n.wallpaperLockPinHint, style: Theme.of(sheetContext).textTheme.bodySmall),
              ),
              if (locked)
                ListTile(
                  leading: const Icon(AIcons.unlocked),
                  title: Text(_isRangeLock ? l10n.visibleRangeUnlock : l10n.wallpaperLockUnlock),
                  onTap: () => Navigator.pop(sheetContext, _LockAction.unlock),
                )
              else if (_isRangeLock)
                ListTile(
                  leading: const Icon(AIcons.locked),
                  title: Text(l10n.visibleRangeLock),
                  onTap: () => Navigator.pop(sheetContext, _LockAction.lock),
                )
              else
                // The group lock needs to know which group to freeze, so it is
                // set from the wallpaper page where that group is on screen.
                ListTile(
                  leading: const Icon(AIcons.locked),
                  title: Text(l10n.wallpaperLockGroupLockHint),
                  enabled: false,
                ),
              ListTile(
                leading: const Icon(AIcons.pin),
                title: Text(l10n.wallpaperLockChangePin),
                onTap: () => Navigator.pop(sheetContext, _LockAction.changePin),
              ),
            ],
          ),
        );
      },
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case _LockAction.lock:
        // Locking is direct: it only adds protection.
        await visibleRangeController.lockWithPreset(visibleRangeController.lastLockPreset);
      case _LockAction.unlock:
        await _unlock(context);
      case _LockAction.changePin:
        await _changePin(context);
    }
  }

  Future<void> _unlock(BuildContext context) async {
    final l10n = context.l10n;
    final pin = await _askPin(context, needConfirmation: false, title: l10n.wallpaperLockNeededTitle);
    if (pin == null || !context.mounted) return;
    if (_isRangeLock) {
      if (!await wallpaperLockService.verify(kind, pin)) {
        if (context.mounted) unawaited(showWarningDialog(context: context, message: l10n.wallpaperLockPinWrong));
        return;
      }
      await visibleRangeController.unlock();
    } else {
      final unlocked = await wallpaperLockService.unlockGroup(pin);
      if (!unlocked && context.mounted) unawaited(showWarningDialog(context: context, message: l10n.wallpaperLockPinWrong));
    }
  }

  /// Current PIN, then the new one twice.
  ///
  /// The current PIN is verified before asking for the new one, so a user who
  /// misremembers it is told at once instead of after typing the replacement.
  Future<void> _changePin(BuildContext context) async {
    final l10n = context.l10n;
    final current = await _askPin(context, needConfirmation: false, title: l10n.wallpaperLockNeededTitle);
    if (current == null || !context.mounted) return;
    if (!await wallpaperLockService.verify(kind, current)) {
      if (context.mounted) unawaited(showWarningDialog(context: context, message: l10n.wallpaperLockPinWrong));
      return;
    }
    final next = await _askPin(context, needConfirmation: true, title: l10n.wallpaperLockChangePin);
    if (next == null) return;
    final changed = await wallpaperLockService.changePin(kind, currentPin: current, nextPin: next);
    if (!changed && context.mounted) unawaited(showWarningDialog(context: context, message: l10n.wallpaperLockPinWrong));
  }

  Future<String?> _askPin(BuildContext context, {required bool needConfirmation, required String title}) => showAvesDialog<String>(
        context: context,
        builder: (context) => PinDialog(needConfirmation: needConfirmation, title: title),
        routeSettings: const RouteSettings(name: PinDialog.routeName),
      );
}

enum _LockAction { lock, unlock, changePin }
