import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_state.dart';

/// The group a view-page step lands on, following the enabled rotation.
///
/// The steps follow the group numbers: up raises the number, down lowers it,
/// and the walk wraps between the first and the last enabled group. Group 0 is
/// deliberately not part of it: with no group playing the page greys the
/// controls instead of entering the rotation from 0, which is the system's own
/// "nothing is playing" state.
///
/// The rotation itself comes from `state.json` (`groups` is the enabled groups
/// in display order), so this agrees with the notification's own switch rather
/// than reconstructing it from the database.
GroupedWallpaperGroup? groupedWallpaperViewGroupTarget({
  required List<GroupedWallpaperGroup> groups,
  required String currentId,
  required int delta,
}) {
  if (delta == 0 || groups.length < 2) return null;
  final index = groups.indexWhere((group) => group.id == currentId);
  if (index < 0) return null;
  final count = groups.length;
  return groups[((index + delta) % count + count) % count];
}
