import 'dart:async';

import 'package:aves/features/wallpaper_lock/model/wallpaper_lock_kind.dart';
import 'package:aves/features/wallpaper_lock/services/wallpaper_lock_service.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/dialogs/aves_dialog.dart';
import 'package:aves/widgets/dialogs/filter_editors/pin_dialog.dart';
import 'package:material_ui/material_ui.dart';

/// Asks for the PIN before an action guarded by [kind].
///
/// Returns true when the action may proceed: the lock is off, already unlocked
/// this session, or the user entered the right PIN. A cancelled dialog and a
/// wrong PIN both return false, so the caller simply does nothing.
///
/// The prompt is a gate, not security: it only makes a stray tap harmless.
Future<bool> ensureWallpaperUnlocked(BuildContext context, WallpaperLockKind kind) async {
  if (!wallpaperLockService.isLocked(kind)) return true;
  final pin = await showAvesDialog<String>(
    context: context,
    builder: (context) => PinDialog(
      needConfirmation: false,
      title: context.l10n.wallpaperLockNeededTitle,
    ),
    routeSettings: const RouteSettings(name: PinDialog.routeName),
  );
  if (pin == null || !context.mounted) return false;
  final unlocked = await wallpaperLockService.unlock(kind, pin);
  if (!context.mounted) return false;
  if (!unlocked) {
    unawaited(showWarningDialog(context: context, message: context.l10n.wallpaperLockPinWrong));
  }
  return unlocked;
}

Future<bool> ensureVisibleRangeUnlocked(BuildContext context) => ensureWallpaperUnlocked(context, WallpaperLockKind.visibleRange);

Future<bool> ensureGroupSwitchUnlocked(BuildContext context) => ensureWallpaperUnlocked(context, WallpaperLockKind.groupSwitch);
