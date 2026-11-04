import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/visible_range/data/default_presets.dart';
import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/features/visible_range/services/visible_range_controller.dart';
import 'package:aves/features/visible_range/services/visible_range_gate.dart';
import 'package:aves/features/visible_range/services/visible_range_locks.dart';
import 'package:aves/model/filters/path.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves_model/aves_model.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../helpers/sqlite3_loader.dart';

/// A locked range freezes the library operations its permissions do not name.
void main() {
  setUpAll(() {
    ensureSqlite3Loaded();
    getIt.registerLazySingleton<p.Context>(() => p.Context(style: p.Style.posix));
  });

  tearDownAll(getIt.reset);

  late AppDatabase db;
  late VisibleRangeController controller;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    controller = VisibleRangeController(injectedDatabase: db, presetLoader: () async => const <VisibleRangePresetDefinition>[]);
    await controller.init();
    VisibleRangeGate.debugController = controller;
  });

  tearDown(() async {
    VisibleRangeGate.debugController = null;
    await db.close();
  });

  Future<void> restrict() => controller.selectBase(presetId: '', name: 'a', filters: {PathFilter('/a')});

  test('an unlocked range withholds nothing', () async {
    await restrict();

    for (final mutation in VisibleRangeMutation.values) {
      expect(VisibleRangeGate.allows(mutation), isTrue, reason: '$mutation');
    }
    expect(visibleRangeLocksEntrySetAction(EntrySetAction.delete), isFalse);
    expect(visibleRangeLocksEntryAction(EntryAction.delete), isFalse);
    expect(visibleRangeLocksChipSetAction(ChipSetAction.delete), isFalse);
  });

  test('a read-only lock withholds every edit but sharing', () async {
    await restrict();
    await controller.lock(permissions: VisibleRangePermissions.readOnly);

    expect(VisibleRangeGate.allows(VisibleRangeMutation.delete), isFalse);
    expect(VisibleRangeGate.allows(VisibleRangeMutation.move), isFalse);
    expect(VisibleRangeGate.allows(VisibleRangeMutation.rename), isFalse);
    expect(VisibleRangeGate.allows(VisibleRangeMutation.edit), isFalse);
    expect(VisibleRangeGate.allows(VisibleRangeMutation.trash), isFalse);
    expect(VisibleRangeGate.allows(VisibleRangeMutation.hide), isFalse);
    expect(VisibleRangeGate.allows(VisibleRangeMutation.vault), isFalse);
    // Read-only still shares, which is the product rule for the default lock.
    expect(VisibleRangeGate.allows(VisibleRangeMutation.share), isTrue);
  });

  test('a manageable lock allows the operations it names', () async {
    await restrict();
    await controller.lock(permissions: VisibleRangePermissions.manageable);

    for (final mutation in [VisibleRangeMutation.delete, VisibleRangeMutation.move, VisibleRangeMutation.rename, VisibleRangeMutation.edit, VisibleRangeMutation.trash, VisibleRangeMutation.hide]) {
      expect(VisibleRangeGate.allows(mutation), isTrue, reason: '$mutation');
    }
    expect(VisibleRangeGate.allows(VisibleRangeMutation.vault), isFalse);
  });

  test('unlocking restores every operation', () async {
    await restrict();
    await controller.lock(permissions: VisibleRangePermissions.readOnly);
    await controller.unlock();

    for (final mutation in VisibleRangeMutation.values) {
      expect(VisibleRangeGate.allows(mutation), isTrue, reason: '$mutation');
    }
  });

  test('maps entry-set actions to the permission each one needs', () async {
    await restrict();
    await controller.lock(permissions: VisibleRangePermissions.readOnly);

    expect(visibleRangeLocksEntrySetAction(EntrySetAction.delete), isTrue);
    expect(visibleRangeLocksEntrySetAction(EntrySetAction.move), isTrue);
    expect(visibleRangeLocksEntrySetAction(EntrySetAction.copy), isTrue);
    expect(visibleRangeLocksEntrySetAction(EntrySetAction.rename), isTrue);
    expect(visibleRangeLocksEntrySetAction(EntrySetAction.rotateCW), isTrue);
    expect(visibleRangeLocksEntrySetAction(EntrySetAction.editTags), isTrue);
    expect(visibleRangeLocksEntrySetAction(EntrySetAction.emptyBin), isTrue);
    // Sharing is allowed by the default lock, and reading is never gated.
    expect(visibleRangeLocksEntrySetAction(EntrySetAction.share), isFalse);
    expect(visibleRangeLocksEntrySetAction(EntrySetAction.select), isFalse);
    expect(visibleRangeLocksEntrySetAction(EntrySetAction.stats), isFalse);
  });

  test('maps viewer and album-grid actions to the permission each one needs', () async {
    await restrict();
    await controller.lock(permissions: VisibleRangePermissions.readOnly);

    expect(visibleRangeLocksEntryAction(EntryAction.delete), isTrue);
    expect(visibleRangeLocksEntryAction(EntryAction.rename), isTrue);
    expect(visibleRangeLocksEntryAction(EntryAction.editDate), isTrue);
    expect(visibleRangeLocksEntryAction(EntryAction.share), isFalse);
    expect(visibleRangeLocksEntryAction(EntryAction.info), isFalse);

    expect(visibleRangeLocksChipSetAction(ChipSetAction.delete), isTrue);
    expect(visibleRangeLocksChipSetAction(ChipSetAction.rename), isTrue);
    expect(visibleRangeLocksChipSetAction(ChipSetAction.hide), isTrue);
    expect(visibleRangeLocksChipSetAction(ChipSetAction.createAlbum), isFalse);
    expect(visibleRangeLocksChipSetAction(ChipSetAction.pin), isFalse);
  });
}
