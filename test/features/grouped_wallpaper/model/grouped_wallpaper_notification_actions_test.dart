import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_notification_actions.dart';
import 'package:flutter_test/flutter_test.dart';

/// `GroupedWallpaperNotificationActions`: the default button set of the
/// notification bar, and the tolerance of a value read back from a file another
/// build wrote.
void main() {
  test('the default keeps the behaviour every earlier build had', () {
    expect(GroupedWallpaperNotificationActions.defaultActions, GroupedWallpaperNotificationActions.wallpaper);
  });

  test('an unknown name reads as the default', () {
    expect(GroupedWallpaperNotificationActions.tryParse('group'), GroupedWallpaperNotificationActions.group);
    expect(GroupedWallpaperNotificationActions.tryParse('wallpaper'), GroupedWallpaperNotificationActions.wallpaper);
    expect(GroupedWallpaperNotificationActions.tryParse(null), GroupedWallpaperNotificationActions.defaultActions);
    expect(GroupedWallpaperNotificationActions.tryParse('GROUP'), GroupedWallpaperNotificationActions.defaultActions);
    expect(GroupedWallpaperNotificationActions.tryParse(3), GroupedWallpaperNotificationActions.defaultActions);
  });
}
