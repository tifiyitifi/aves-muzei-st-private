import 'package:aves/features/grouped_wallpaper/services/grouped_wallpaper_empty_notice.dart';
import 'package:flutter_test/flutter_test.dart';

/// The dialog is an explanation, not a recurring warning: an empty group is
/// reported once, and only a successful bake starts a new episode.
void main() {
  test('an empty group is reported once per episode', () {
    final notice = GroupedWallpaperEmptyNotice();
    var notifications = 0;
    notice.addListener(() => notifications++);

    expect(notice.isPending, isFalse);
    notice.report(groupId: 'a', groupName: 'A');
    expect(notice.isPending, isTrue);
    expect(notice.groupName, 'A');
    expect(notifications, 1);

    // A sync loop reporting the same empty group must not bring the dialog back.
    notice.report(groupId: 'a', groupName: 'A');
    expect(notifications, 1);

    notice.dismiss();
    expect(notice.isPending, isFalse);
    expect(notifications, 2);
    notice.report(groupId: 'a', groupName: 'A');
    expect(notice.isPending, isFalse);
    expect(notifications, 2);

    // Another empty group is a new explanation.
    notice.report(groupId: 'b', groupName: 'B');
    expect(notice.isPending, isTrue);
    expect(notice.groupName, 'B');
    // Going back to one already explained in this episode stays quiet.
    notice.dismiss();
    notice.report(groupId: 'a', groupName: 'A');
    expect(notice.isPending, isFalse);

    // A successful bake ends the episode, so the same group can explain itself
    // again after it was fixed and emptied later.
    notice.clearEpisode();
    expect(notice.isPending, isFalse);
    notice.report(groupId: 'a', groupName: 'A');
    expect(notice.isPending, isTrue);
  });
}
