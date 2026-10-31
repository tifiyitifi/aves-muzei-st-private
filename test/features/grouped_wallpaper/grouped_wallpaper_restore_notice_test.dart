import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_state.dart';
import 'package:aves/features/grouped_wallpaper/services/grouped_wallpaper_restore_notice.dart';
import 'package:aves/features/grouped_wallpaper/services/wallpaper_engine_link.dart';
import 'package:flutter_test/flutter_test.dart';

/// `GroupedWallpaperRestoreNotice`: the app-side notice over the platform's
/// "the wallpaper was in use and is gone" answer.
void main() {
  late WallpaperEngineLink link;
  late _FakeConnection connection;
  late GroupedWallpaperRestoreNotice notice;

  setUp(() {
    link = WallpaperEngineLink();
    connection = _FakeConnection();
    notice = GroupedWallpaperRestoreNotice(link: link);
  });

  test('offers nothing until the platform says the wallpaper is gone', () async {
    link.attach(connection);

    expect(notice.isOffered, isFalse);
    await notice.refresh();
    expect(notice.isOffered, isFalse);

    connection.offer = true;
    await notice.refresh();
    expect(notice.isOffered, isTrue);
  });

  test('a detached link never offers', () async {
    await notice.refresh();

    expect(notice.isOffered, isFalse);
  });

  test('dismissing hides the loss the user already saw', () async {
    link.attach(connection);
    connection.offer = true;
    await notice.refresh();

    notice.dismiss();
    expect(notice.isOffered, isFalse);

    // The platform still reports the same loss; re-probing must not nag.
    await notice.refresh();
    expect(notice.isOffered, isFalse);
  });

  test('a fresh loss is offered again after the user dismissed an older one', () async {
    link.attach(connection);
    connection.offer = true;
    await notice.refresh();
    notice.dismiss();

    // Re-applied: the answer clears.
    connection.offer = false;
    await notice.refresh();
    expect(notice.isOffered, isFalse);

    // A later loss is a new event, not the one that was dismissed.
    connection.offer = true;
    await notice.refresh();
    expect(notice.isOffered, isTrue);
  });

  test('notifies only when the answer changes', () async {
    link.attach(connection);
    var notifications = 0;
    notice.addListener(() => notifications++);

    connection.offer = false;
    await notice.refresh();
    expect(notifications, 0);

    connection.offer = true;
    await notice.refresh();
    expect(notifications, 1);

    await notice.refresh();
    expect(notifications, 1);

    notice.dismiss();
    expect(notifications, 2);
  });

  test('re-applying opens the system picker', () async {
    link.attach(connection);

    expect(await notice.reapply(), isTrue);
    expect(connection.chooserOpened, isTrue);
  });
}

class _FakeConnection implements WallpaperEngineConnection {
  bool offer = false;
  bool chooserOpened = false;

  @override
  Future<bool> isActive() async => false;

  @override
  Future<bool> restoreOffer() async => offer;

  @override
  Future<bool> openChooser() async {
    chooserOpened = true;
    return true;
  }

  @override
  Future<bool> isDisabled() async => false;

  @override
  Future<GroupedWallpaperState?> readState() async => null;

  @override
  Future<GroupedWallpaperState?> readDisplayedState() async => null;

  @override
  Future<String?> currentPhotoPath() async => null;

  @override
  Future<String?> currentEffectPhotoPath() async => null;

  @override
  Future<GroupedWallpaperSyncResult> prepare({bool activation = false}) async => GroupedWallpaperSyncResult.notActive;

  @override
  Future<GroupedWallpaperSyncResult> syncNow() async => GroupedWallpaperSyncResult.notActive;

  @override
  Future<void> refreshSchedule() async {}

  @override
  Future<void> setDisabled(bool disabled) async {}

  @override
  Future<bool> isNotificationEnabled() async => false;

  @override
  Future<void> setNotification(bool enabled) async {}

  @override
  Future<void> setHistoryLimit(int limit) async {}

  @override
  Future<void> clearRewind() async {}

  @override
  Future<void> refreshLock() async {}

  @override
  Future<GroupedWallpaperSyncResult> previousArtwork() async => GroupedWallpaperSyncResult.notActive;

  @override
  Future<GroupedWallpaperSyncResult> nextArtwork() async => GroupedWallpaperSyncResult.notActive;
}
