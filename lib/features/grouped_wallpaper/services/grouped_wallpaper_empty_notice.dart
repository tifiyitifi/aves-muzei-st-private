import 'package:flutter/foundation.dart';

/// Surfaces "the wallpaper group has no photo" inside the app.
///
/// The engine keeps the frame already on screen instead of replacing it with the
/// placeholder, so a switch to an empty group is intentionally invisible on the
/// wallpaper. Without an explanation the action looks broken; this notice is what
/// lets the wallpaper page say once why nothing changed.
///
/// The dedupe is per **empty episode**: every empty group is reported once, and a
/// sync loop, an interval run or switching back to a group already explained in
/// this episode stays quiet. A successful bake ends the episode, so the next
/// empty group — or a group that was fixed and emptied again — is explained again.
class GroupedWallpaperEmptyNotice extends ChangeNotifier {
  final Set<String> _reportedGroupIds = {};
  String? _groupId;
  String? _groupName;

  /// Whether a dialog is waiting to be shown.
  bool get isPending => _groupId != null;

  /// The name of the empty group to show in the dialog, or null when none waits.
  String? get groupName => _groupId == null ? null : _groupName;

  /// Records that [groupId] resolved to no photo.
  void report({required String groupId, required String groupName}) {
    if (!_reportedGroupIds.add(groupId)) return;
    _groupId = groupId;
    _groupName = groupName;
    notifyListeners();
  }

  /// Marks the pending explanation as shown; the group stays reported.
  void dismiss() {
    if (_groupId == null) return;
    _groupId = null;
    _groupName = null;
    notifyListeners();
  }

  /// A non-empty bake ended the episode, so later empty groups explain themselves.
  void clearEpisode() {
    _reportedGroupIds.clear();
    if (_groupId == null) return;
    _groupId = null;
    _groupName = null;
    notifyListeners();
  }
}

/// The process-wide notice, like the restore notice.
final groupedWallpaperEmptyNotice = GroupedWallpaperEmptyNotice();
