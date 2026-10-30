import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/wallpaper_lock/db/wallpaper_lock_store.dart';
import 'package:aves/features/wallpaper_lock/model/wallpaper_lock_kind.dart';
import 'package:aves/features/wallpaper_lock/services/wallpaper_lock_service.dart';
import 'package:aves/services/security_service.dart';
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/sqlite3_loader.dart';

/// The PIN gates: what verifies, what unlocks only for the session, and what
/// stays untouched when the other lock changes.
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

  test('both locks start off', () {
    expect(service.visibleRangeLocked, isFalse);
    expect(service.groupSwitchLocked, isFalse);
    expect(service.isEnabled(WallpaperLockKind.visibleRange), isFalse);
  });

  test('enabling locks, unlocking is session-only, backgrounding relocks', () async {
    await service.enable(WallpaperLockKind.visibleRange);
    expect(service.visibleRangeLocked, isTrue);

    expect(await service.unlock(WallpaperLockKind.visibleRange, '0000'), isFalse);
    expect(service.visibleRangeLocked, isTrue);

    expect(await service.unlock(WallpaperLockKind.visibleRange, WallpaperLockService.defaultPin), isTrue);
    expect(service.visibleRangeLocked, isFalse);
    expect(service.isUnlocked(WallpaperLockKind.visibleRange), isTrue);

    // Leaving the app ends the unlocked session; coming back must ask again.
    service.didChangeAppLifecycleState(AppLifecycleState.paused);
    expect(service.visibleRangeLocked, isTrue);

    service.relock(WallpaperLockKind.visibleRange);
    expect(service.visibleRangeLocked, isTrue);
  });

  test('changing the PIN needs the current one', () async {
    expect(await service.changePin(WallpaperLockKind.visibleRange, currentPin: '0000', nextPin: '2468'), isFalse);
    expect(await service.verify(WallpaperLockKind.visibleRange, WallpaperLockService.defaultPin), isTrue);

    expect(await service.changePin(WallpaperLockKind.visibleRange, currentPin: WallpaperLockService.defaultPin, nextPin: '2468'), isTrue);
    expect(await service.verify(WallpaperLockKind.visibleRange, WallpaperLockService.defaultPin), isFalse);
    expect(await service.verify(WallpaperLockKind.visibleRange, '2468'), isTrue);
    expect(await service.unlock(WallpaperLockKind.visibleRange, '2468'), isTrue);
  });

  test('the PIN must keep four digits', () async {
    expect(await service.changePin(WallpaperLockKind.groupSwitch, currentPin: WallpaperLockService.defaultPin, nextPin: '123'), isFalse);
    expect(await service.verify(WallpaperLockKind.groupSwitch, WallpaperLockService.defaultPin), isTrue);
  });

  test('disabling needs the PIN and keeps the lock on when it is wrong', () async {
    await service.enable(WallpaperLockKind.groupSwitch);

    expect(await service.disable(WallpaperLockKind.groupSwitch, '0000'), isFalse);
    expect(service.groupSwitchLocked, isTrue);

    expect(await service.disable(WallpaperLockKind.groupSwitch, WallpaperLockService.defaultPin), isTrue);
    expect(service.groupSwitchLocked, isFalse);
    expect(service.isEnabled(WallpaperLockKind.groupSwitch), isFalse);
  });

  test('the two locks are independent', () async {
    await service.enable(WallpaperLockKind.groupSwitch);

    expect(await service.unlock(WallpaperLockKind.visibleRange, WallpaperLockService.defaultPin), isTrue);
    expect(service.groupSwitchLocked, isTrue);

    expect(await service.disable(WallpaperLockKind.visibleRange, WallpaperLockService.defaultPin), isFalse);
    expect(service.isEnabled(WallpaperLockKind.groupSwitch), isTrue);
  });

  test('each PIN is stored under its own key', () async {
    await service.changePin(WallpaperLockKind.visibleRange, currentPin: WallpaperLockService.defaultPin, nextPin: '1111');
    await service.changePin(WallpaperLockKind.groupSwitch, currentPin: WallpaperLockService.defaultPin, nextPin: '2222');

    expect(security.values[WallpaperLockStore.pinKeyOf(WallpaperLockKind.visibleRange)], '1111');
    expect(security.values[WallpaperLockStore.pinKeyOf(WallpaperLockKind.groupSwitch)], '2222');
  });

  test('flags survive a new service over the same store', () async {
    await service.enable(WallpaperLockKind.visibleRange);
    final reloaded = WallpaperLockService(security: security, store: store);
    await reloaded.init();
    addTearDown(reloaded.dispose);

    expect(reloaded.visibleRangeLocked, isTrue);
    // A session unlock is memory only.
    expect(reloaded.isUnlocked(WallpaperLockKind.visibleRange), isFalse);
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
