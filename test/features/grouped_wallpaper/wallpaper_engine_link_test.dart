import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_state.dart';
import 'package:aves/features/grouped_wallpaper/services/wallpaper_engine_link.dart';
import 'package:flutter_test/flutter_test.dart';

/// `WallpaperEngineLink`: the page-facing contract, its cached active/disabled
/// flags and the inert behaviour before the engine attaches.
void main() {
  late WallpaperEngineLink link;
  late _FakeConnection connection;

  setUp(() {
    link = WallpaperEngineLink();
    connection = _FakeConnection();
  });

  test('a detached link is inert', () async {
    expect(link.isAttached, isFalse);
    expect(link.isActive, isFalse);
    expect(link.isDisabled, isFalse);
    expect(link.isPlaying, isFalse);
    expect(await link.refreshActive(), isFalse);
    expect(await link.readState(), isNull);
    expect(await link.prepare(), GroupedWallpaperSyncResult.notActive);
    expect(await link.syncNow(), GroupedWallpaperSyncResult.notActive);
    expect(await link.openChooser(), isFalse);
  });

  test('refreshActive caches the probe result', () async {
    link.attach(connection);

    expect(link.isActive, isFalse);
    expect(await link.refreshActive(), isTrue);
    expect(link.isActive, isTrue);

    connection.active = false;
    // Still the cached value until the page asks again.
    expect(link.isActive, isTrue);
    expect(await link.refreshActive(), isFalse);
    expect(link.isActive, isFalse);
  });

  test('a failed probe counts as not active', () async {
    connection.error = StateError('channel gone');
    link.attach(connection);

    expect(await link.refreshActive(), isFalse);
    expect(link.isActive, isFalse);
  });

  test('restoreOffer is only true once the platform says so', () async {
    // Detached: nothing can be offered, whatever the platform would answer.
    expect(await link.refreshRestoreOffer(), isFalse);

    link.attach(connection);
    expect(await link.refreshRestoreOffer(), isFalse);

    connection.offer = true;
    expect(await link.refreshRestoreOffer(), isTrue);

    connection.offer = false;
    expect(await link.refreshRestoreOffer(), isFalse);
  });

  test('a failed restore probe offers nothing', () async {
    // A wrong offer would open a picker over a wallpaper the user still has.
    connection.error = StateError('channel gone');
    link.attach(connection);

    expect(await link.refreshRestoreOffer(), isFalse);
  });

  test('playing needs both the service on screen and the feature on', () async {
    link.attach(connection);
    await link.refreshActive();
    await link.refreshDisabled();
    expect(link.isPlaying, isTrue);

    // Turned off: the service keeps the last frame but the feature is not
    // following its group any more.
    await link.setDisabled(true);
    expect(link.isDisabled, isTrue);
    expect(link.isActive, isTrue);
    expect(link.isPlaying, isFalse);

    // The service is no longer the wallpaper: also not playing.
    await link.setDisabled(false);
    connection.active = false;
    await link.refreshActive();
    expect(link.isPlaying, isFalse);
  });

  test('refreshDisabled reads the saved switch', () async {
    link.attach(connection);
    connection.disabled = true;

    await link.refreshDisabled();

    expect(link.isDisabled, isTrue);
  });

  test('the notification switch is cached and written through', () async {
    link.attach(connection);
    connection.notification = false;

    expect(link.notificationEnabled, isTrue);
    await link.refreshNotification();
    expect(link.notificationEnabled, isFalse);

    await link.setNotification(true);
    expect(link.notificationEnabled, isTrue);
    expect(connection.notification, isTrue);
  });

  test('a detached link reports the notification as on', () async {
    expect(link.notificationEnabled, isTrue);
    await link.refreshNotification();
    expect(link.notificationEnabled, isTrue);
  });

  test('the scroll effect switch is cached and written through', () async {
    link.attach(connection);
    connection.scrollEffect = false;

    expect(link.scrollEffectEnabled, isTrue);
    await link.refreshScrollEffect();
    expect(link.scrollEffectEnabled, isFalse);

    await link.setScrollEffect(true);
    expect(link.scrollEffectEnabled, isTrue);
    expect(connection.scrollEffect, isTrue);
  });

  test('a detached link reports the scroll effect as on', () async {
    expect(link.scrollEffectEnabled, isTrue);
    await link.refreshScrollEffect();
    expect(link.scrollEffectEnabled, isTrue);
  });

  test('delegates the engine actions', () async {
    link.attach(connection);
    connection.state = const GroupedWallpaperState(
      status: GroupedWallpaperStatus.ready,
      groupNumber: 2,
      groupName: 'DCIM',
      current: 0,
      slots: [
        GroupedWallpaperSlot(id: 0, entryId: 7, uri: 'content://7', title: 'IMG_7', photo: 'slots/0/photo.png'),
      ],
    );

    expect((await link.readState())?.groupNumber, 2);
    expect(await link.prepare(), GroupedWallpaperSyncResult.unchanged);
    expect(connection.prepares, 1);
    expect(await link.syncNow(), GroupedWallpaperSyncResult.baked);
    expect(connection.syncs, 1);
    expect(await link.openChooser(), isTrue);
  });

  test('detaching forgets the engine and the cached flags', () async {
    link.attach(connection);
    await link.refreshActive();
    await link.refreshDisabled();
    expect(link.isActive, isTrue);

    link.detach();

    expect(link.isAttached, isFalse);
    expect(link.isActive, isFalse);
    expect(link.isDisabled, isFalse);
    expect(await link.syncNow(), GroupedWallpaperSyncResult.notActive);
  });
}

class _FakeConnection implements WallpaperEngineConnection {
  bool active = true;
  bool disabled = false;
  Object? error;
  int prepares = 0;
  int syncs = 0;
  GroupedWallpaperState? state;

  @override
  Future<bool> isActive() async {
    final failure = error;
    if (failure != null) throw failure;
    return active;
  }

  @override
  Future<bool> restoreOffer() async {
    final failure = error;
    if (failure != null) throw failure;
    return offer;
  }

  bool offer = false;

  @override
  Future<bool> isDisabled() async => disabled;

  @override
  Future<GroupedWallpaperState?> readState() async => state;

  @override
  Future<GroupedWallpaperState?> readDisplayedState() async => state;

  @override
  Future<String?> currentPhotoPath() async => null;

  @override
  Future<String?> currentEffectPhotoPath() async => null;

  @override
  Future<GroupedWallpaperSyncResult> prepare({bool activation = false}) async {
    prepares++;
    return GroupedWallpaperSyncResult.unchanged;
  }

  @override
  Future<GroupedWallpaperSyncResult> syncNow() async {
    syncs++;
    return GroupedWallpaperSyncResult.baked;
  }

  @override
  Future<void> refreshSchedule() async => schedules++;

  int schedules = 0;

  @override
  Future<void> setDisabled(bool disabled) async => this.disabled = disabled;

  @override
  Future<bool> isNotificationEnabled() async => notification;

  @override
  Future<void> setNotification(bool enabled) async => notification = enabled;

  bool notification = true;

  @override
  Future<bool> isScrollEffectEnabled() async => scrollEffect;

  @override
  Future<void> setScrollEffect(bool enabled) async => scrollEffect = enabled;

  bool scrollEffect = true;

  @override
  Future<void> setHistoryLimit(int limit) async => historyLimit = limit;

  int historyLimit = 200;

  @override
  Future<void> refreshLock() async {}

  @override
  Future<GroupedWallpaperSyncResult> previousArtwork() async => GroupedWallpaperSyncResult.unchanged;

  @override
  Future<GroupedWallpaperSyncResult> nextArtwork() async => GroupedWallpaperSyncResult.unchanged;

  @override
  Future<bool> openChooser() async => true;
}
