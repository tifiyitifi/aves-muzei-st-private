import 'package:aves/features/grouped_wallpaper/services/wallpaper_engine_link.dart';
import 'package:flutter/foundation.dart';

/// Surfaces "the system dropped the grouped wallpaper" inside the app.
///
/// An OEM that resets a live wallpaper on an app update (MIUI observed) also
/// tends to silence that app's notifications, so a notification is not a channel
/// the user reads. Muzei answers the same problem the same way: it checks on
/// entry and offers one tap to re-apply, with no attempt at a silent rebind.
///
/// The decision stays on the platform ([WallpaperEngineLink.restoreOffer]):
/// the OEM's fallback and a live wallpaper the user picked are indistinguishable
/// from Dart, and offering the wrong one would send the user to a picker that
/// takes over a wallpaper they never lost. This class only caches the answer,
/// because the value has to be readable from a synchronous build.
class GroupedWallpaperRestoreNotice extends ChangeNotifier {
  final WallpaperEngineLink _link;
  bool _offered = false;
  bool _dismissed = false;

  new({WallpaperEngineLink? link}) : _link = link ?? wallpaperEngineLink;

  /// Whether a notice should be on screen now.
  ///
  /// A dismissal only silences the loss the user has already seen: a fresh loss
  /// ([refresh] answering true after it answered false) is a new event.
  bool get isOffered => _offered && !_dismissed;

  /// Re-asks the platform and notifies when the answer changed.
  Future<void> refresh() async {
    final offered = await _link.refreshRestoreOffer();
    if (offered == _offered) return;
    _offered = offered;
    if (offered) _dismissed = false;
    notifyListeners();
  }

  /// Hides the notice for the rest of this loss.
  void dismiss() {
    if (_dismissed) return;
    _dismissed = true;
    notifyListeners();
  }

  /// Opens the system picker on the grouped service.
  ///
  /// The picker takes over the screen, so the state is not cleared here: the
  /// caller re-reads it on resume, and only a committed switch drops the notice.
  Future<bool> reapply() => _link.openChooser();
}

/// The process-wide notice, like [wallpaperEngineLink].
final groupedWallpaperRestoreNotice = GroupedWallpaperRestoreNotice();
