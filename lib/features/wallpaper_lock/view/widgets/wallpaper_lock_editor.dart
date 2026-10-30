import 'dart:async';

import 'package:aves/features/meta_settings/model/setting_def.dart';
import 'package:aves/features/wallpaper_lock/model/wallpaper_lock_kind.dart';
import 'package:aves/features/wallpaper_lock/services/wallpaper_lock_service.dart';
import 'package:aves/features/wallpaper_lock/view/wallpaper_lock_prompt.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/common/identity/aves_list_subtitle.dart';
import 'package:aves/widgets/dialogs/aves_dialog.dart';
import 'package:aves/widgets/dialogs/filter_editors/pin_dialog.dart';
import 'package:material_ui/material_ui.dart';

/// One settings row per lock: state, and the sheet that changes it.
///
/// The row follows [wallpaperLockService] instead of reading the store, so
/// unlocking in the sheet immediately changes what the row (and every guarded
/// page) offers.
class WallpaperLockEditor extends StatelessWidget {
  final SettingDef def;

  final WallpaperLockKind kind;

  const new({super.key, required this.def, required this.kind});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: wallpaperLockService,
        builder: (context, _) {
          final enabled = wallpaperLockService.isEnabled(kind);
          final unlocked = wallpaperLockService.isUnlocked(kind);
          final l10n = context.l10n;
          final subtitle = !enabled
              ? l10n.wallpaperLockSubtitleDisabled
              : unlocked
                  ? l10n.wallpaperLockSubtitleUnlocked
                  : l10n.wallpaperLockSubtitleEnabled;
          return ListTile(
            title: Text(def.title(context)),
            subtitle: AvesListSubtitle(subtitle),
            trailing: Icon(enabled && !unlocked ? AIcons.locked : AIcons.unlocked, size: 20),
            onTap: () => unawaited(_openSheet(context)),
          );
        },
      );

  Future<void> _openSheet(BuildContext context) async {
    final action = await showModalBottomSheet<_LockAction>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final l10n = sheetContext.l10n;
        final enabled = wallpaperLockService.isEnabled(kind);
        final unlocked = wallpaperLockService.isUnlocked(kind);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(l10n.wallpaperLockPinHint, style: Theme.of(sheetContext).textTheme.bodySmall),
              ),
              if (!enabled)
                ListTile(
                  leading: const Icon(AIcons.locked),
                  title: Text(l10n.wallpaperLockEnable),
                  onTap: () => Navigator.pop(sheetContext, _LockAction.enable),
                )
              else ...[
                if (unlocked)
                  ListTile(
                    leading: const Icon(AIcons.locked),
                    title: Text(l10n.wallpaperLockRelock),
                    onTap: () => Navigator.pop(sheetContext, _LockAction.relock),
                  )
                else
                  ListTile(
                    leading: const Icon(AIcons.unlocked),
                    title: Text(l10n.wallpaperLockUnlock),
                    onTap: () => Navigator.pop(sheetContext, _LockAction.unlock),
                  ),
                ListTile(
                  leading: const Icon(AIcons.pin),
                  title: Text(l10n.wallpaperLockChangePin),
                  onTap: () => Navigator.pop(sheetContext, _LockAction.changePin),
                ),
                ListTile(
                  leading: const Icon(AIcons.unselected),
                  title: Text(l10n.wallpaperLockDisable),
                  onTap: () => Navigator.pop(sheetContext, _LockAction.disable),
                ),
              ],
            ],
          ),
        );
      },
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case _LockAction.enable:
        await wallpaperLockService.enable(kind);
      case _LockAction.unlock:
        await ensureWallpaperUnlocked(context, kind);
      case _LockAction.relock:
        wallpaperLockService.relock(kind);
      case _LockAction.changePin:
        await _changePin(context);
      case _LockAction.disable:
        await _disable(context);
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

  Future<void> _disable(BuildContext context) async {
    final l10n = context.l10n;
    final pin = await _askPin(context, needConfirmation: false, title: l10n.wallpaperLockNeededTitle);
    if (pin == null) return;
    final disabled = await wallpaperLockService.disable(kind, pin);
    if (!disabled && context.mounted) unawaited(showWarningDialog(context: context, message: l10n.wallpaperLockPinWrong));
  }

  Future<String?> _askPin(BuildContext context, {required bool needConfirmation, required String title}) => showAvesDialog<String>(
        context: context,
        builder: (context) => PinDialog(needConfirmation: needConfirmation, title: title),
        routeSettings: const RouteSettings(name: PinDialog.routeName),
      );
}

enum _LockAction { enable, unlock, relock, changePin, disable }
