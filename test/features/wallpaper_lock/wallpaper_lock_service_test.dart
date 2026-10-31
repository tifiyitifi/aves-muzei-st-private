import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/wallpaper_lock/db/wallpaper_lock_store.dart';
import 'package:aves/features/wallpaper_lock/model/wallpaper_lock_kind.dart';
import 'package:aves/features/wallpaper_lock/services/wallpaper_lock_service.dart';
import 'package:aves/services/security_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/sqlite3_loader.dart';

/// The PIN locks: the visible range's state is the range row, and the group
/// switch lock is the persisted flag tested here.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(ensureSqlite3Loaded);

  late AppDatabase db;
  late WallpaperLockStore store;
  late _FakeSecurityService security;
  late WallpaperLockService service;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.customSelect('SELECT 1').get();
    store = WallpaperLockStore(db);
    security = _FakeSecurityService();
    service = WallpaperLockService(security: security, store: store);
    await service.init();
  });

  tearDown(() async {
    service.dispose();
    await db.close();
  });

  test('an unwritten PIN is the default, and any other value fails', () async {
    expect(await service.verify(WallpaperLockKind.visibleRange, WallpaperLockService.defaultPin), isTrue);
    expect(await service.verify(WallpaperLockKind.visibleRange, '0000'), isFalse);
    expect(await service.verify(WallpaperLockKind.groupSwitch, WallpaperLockService.defaultPin), isTrue);
  });

  test('the group switch starts unlocked', () {
    expect(service.groupSwitchLocked, isFalse);
    expect(service.groupSwitchGroupId, isNull);
  });

  test('locking records the group without asking for a PIN', () async {
    await service.lockGroup('wallpaper.group.dcim');

    expect(service.groupSwitchLocked, isTrue);
    expect(service.groupSwitchGroupId, 'wallpaper.group.dcim');
  });

  test('unlocking needs the PIN and keeps the lock when it is wrong', () async {
    await service.lockGroup('wallpaper.group.dcim');

    expect(await service.unlockGroup('0000'), isFalse);
    expect(service.groupSwitchLocked, isTrue);
    expect(service.groupSwitchGroupId, 'wallpaper.group.dcim');

    expect(await service.unlockGroup(WallpaperLockService.defaultPin), isTrue);
    expect(service.groupSwitchLocked, isFalse);
    expect(service.groupSwitchGroupId, isNull);
  });

  test('changing the PIN needs the current one', () async {
    expect(await service.changePin(WallpaperLockKind.visibleRange, currentPin: '0000', nextPin: '2468'), isFalse);
    expect(await service.verify(WallpaperLockKind.visibleRange, WallpaperLockService.defaultPin), isTrue);

    expect(await service.changePin(WallpaperLockKind.visibleRange, currentPin: WallpaperLockService.defaultPin, nextPin: '2468'), isTrue);
    expect(await service.verify(WallpaperLockKind.visibleRange, WallpaperLockService.defaultPin), isFalse);
    expect(await service.verify(WallpaperLockKind.visibleRange, '2468'), isTrue);
  });

  test('the PIN must keep four digits', () async {
    expect(await service.changePin(WallpaperLockKind.groupSwitch, currentPin: WallpaperLockService.defaultPin, nextPin: '123'), isFalse);
    expect(await service.verify(WallpaperLockKind.groupSwitch, WallpaperLockService.defaultPin), isTrue);
  });

  test('the lock survives a new service over the same store', () async {
    await service.lockGroup('wallpaper.group.pictures');

    final reloaded = WallpaperLockService(security: security, store: store);
    await reloaded.init();
    addTearDown(reloaded.dispose);

    expect(reloaded.groupSwitchLocked, isTrue);
    expect(reloaded.groupSwitchGroupId, 'wallpaper.group.pictures');
  });

  test('each PIN is stored under its own key', () async {
    await service.changePin(WallpaperLockKind.visibleRange, currentPin: WallpaperLockService.defaultPin, nextPin: '1111');
    await service.changePin(WallpaperLockKind.groupSwitch, currentPin: WallpaperLockService.defaultPin, nextPin: '2222');

    expect(security.values[WallpaperLockStore.pinKeyOf(WallpaperLockKind.visibleRange)], '1111');
    expect(security.values[WallpaperLockStore.pinKeyOf(WallpaperLockKind.groupSwitch)], '2222');
  });

  test('unlocking the group uses the group PIN only', () async {
    await service.changePin(WallpaperLockKind.visibleRange, currentPin: WallpaperLockService.defaultPin, nextPin: '1111');
    await service.lockGroup('wallpaper.group.dcim');

    // The visible range's PIN must not open the wallpaper lock.
    expect(await service.unlockGroup('1111'), isFalse);
    expect(await service.unlockGroup(WallpaperLockService.defaultPin), isTrue);
  });
}

class _FakeSecurityService implements SecurityService {
  final Map<String, Object?> values = {};

  @override
  Future<bool> writeValue<T>(String key, T? value) async {
    values[key] = value;
    return true;
  }

  @override
  Future<T?> readValue<T>(String key) async => values[key] as T?;
}
