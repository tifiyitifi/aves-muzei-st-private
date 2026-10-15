import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/app_meta/app_meta_store.dart';
import 'package:aves/features/drift_db/migration/legacy_import_progress.dart';
import 'package:aves/features/drift_db/migration/legacy_import_state_store.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/sqlite3_loader.dart';

void main() {
  setUpAll(ensureSqlite3Loaded);

  late AppDatabase db;
  late AppMetaStore appMeta;
  late LegacyImportStateStore state;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    appMeta = AppMetaStore(db);
    state = LegacyImportStateStore(appMeta);
  });

  tearDown(() => db.close());

  test('defaults to pending/preparing on an empty database', () async {
    final snapshot = await state.read();
    expect(snapshot.status, LegacyImportStatus.pending);
    expect(snapshot.phase, LegacyImportPhase.preparing);
  });

  test('honours the legacy done marker when the newer state is absent', () async {
    await appMeta.write({LegacyImportStateStore.legacyDoneKey: 'true'});
    expect((await state.read()).status, LegacyImportStatus.done);
  });

  test('tolerates a corrupt status/phase name instead of throwing', () async {
    await appMeta.write({
      LegacyImportStateStore.statusKey: 'not-a-status',
      LegacyImportStateStore.phaseKey: 'not-a-phase',
      LegacyImportStateStore.copiedKey: '7',
    });
    // One dirty row must not brick every subsequent read (and thus every init).
    final snapshot = await state.read();
    expect(snapshot.status, LegacyImportStatus.pending);
    expect(snapshot.phase, LegacyImportPhase.preparing);
    expect(snapshot.copiedRows, 7);
  });

  test('a corrupt status still degrades to the legacy done marker', () async {
    await appMeta.write({
      LegacyImportStateStore.statusKey: 'not-a-status',
      LegacyImportStateStore.legacyDoneKey: 'true',
    });
    expect((await state.read()).status, LegacyImportStatus.done);
  });
}
