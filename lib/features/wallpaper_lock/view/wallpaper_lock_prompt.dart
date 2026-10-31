import 'dart:async';

import 'package:aves/features/wallpaper_lock/model/wallpaper_lock_kind.dart';
import 'package:aves/features/wallpaper_lock/services/wallpaper_lock_service.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/dialogs/aves_dialog.dart';
import 'package:aves/widgets/dialogs/filter_editors/pin_dialog.dart';
import 'package:material_ui/material_ui.dart';

/// Asks for the PIN of [kind] and checks it.
///
/// Returns true when the user entered the right PIN. A cancelled dialog and a
/// wrong PIN both return false, so the caller simply does nothing. Nothing is
/// remembered: proving the PIN allows the one action that asked, which is what
/// makes locking and unlocking independent of a foreground session.
///
/// The prompt is a gate, not security: it only makes a stray tap harmless.
Future<bool> confirmWallpaperPin(BuildContext context, WallpaperLockKind kind) async {
  final pin = await showAvesDialog<String>(
    context: context,
    builder: (context) => PinDialog(
      needConfirmation: false,
      title: context.l10n.wallpaperLockNeededTitle,
    ),
    routeSettings: const RouteSettings(name: PinDialog.routeName),
  );
  if (pin == null || !context.mounted) return false;
  final valid = await wallpaperLockService.verify(kind, pin);
  if (!context.mounted) return false;
  if (!valid) {
    unawaited(showWarningDialog(context: context, message: context.l10n.wallpaperLockPinWrong));
  }
  return valid;
}

/// Proves the visible-range PIN before touching a locked range.
///
/// Used both to unlock the range and to temporarily ignore it: both lift a
/// restriction the lock protects, so both require the PIN.
Future<bool> ensureVisibleRangeUnlocked(BuildContext context) => confirmWallpaperPin(context, WallpaperLockKind.visibleRange);

/// Asks for the group's PIN and clears the group switch lock.
///
/// Unlocking is a state change, not a one-action proof: the lock stays off until
/// the user locks the group again, even across a process restart.
Future<bool> promptGroupSwitchUnlock(BuildContext context) async {
  final pin = await showAvesDialog<String>(
    context: context,
    builder: (context) => PinDialog(
      needConfirmation: false,
      title: context.l10n.wallpaperLockNeededTitle,
    ),
    routeSettings: const RouteSettings(name: PinDialog.routeName),
  );
  if (pin == null || !context.mounted) return false;
  final unlocked = await wallpaperLockService.unlockGroup(pin);
  if (!context.mounted) return unlocked;
  if (!unlocked) {
    unawaited(showWarningDialog(context: context, message: context.l10n.wallpaperLockPinWrong));
  }
  return unlocked;
}
