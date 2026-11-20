import 'package:aves/features/batch_ops/model/batch_result.dart';
import 'package:aves/features/drift_db/app_database.dart';
import 'package:drift/drift.dart';

/// Owns the `batch_profiles` table.
///
/// A profile is a named action chain plus which kind of run it belongs to. The
/// seeded default keeps an empty chain: normal batch processing starts from
/// "choose the actions", not from a preset that silently alters photos.
class BatchProfileStore {
  /// Stable id of the seeded default profile.
  static const String defaultProfileId = 'default';

  final AppDatabase db;

  new(this.db);

  Future<List<BatchProfile>> getProfiles(BatchProfileKind kind) async {
    final query = db.select(db.batchProfileRows)
      ..where((t) => t.kind.equals(kind.name))
      ..orderBy([
        (t) => OrderingTerm.asc(t.sortOrder),
        (t) => OrderingTerm.asc(t.createdAt),
      ]);
    return (await query.get()).map(BatchProfile.fromRow).toList(growable: false);
  }

  /// Seeds the default profile once per kind.
  Future<void> ensureSeeded(BatchProfileKind kind) async {
    final existing = await (db.select(db.batchProfileRows)..where((t) => t.kind.equals(kind.name))..limit(1)).getSingleOrNull();
    if (existing != null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.into(db.batchProfileRows).insert(
      BatchProfileRowsCompanion.insert(
        id: kind == BatchProfileKind.batch ? defaultProfileId : '$defaultProfileId-${kind.name}',
        // Empty means "the localized default name"; the view resolves it so the
        // database never stores a translated string.
        name: '',
        actionsJson: const Value('[]'),
        kind: Value(kind.name),
        sortOrder: const Value(0),
        isActive: const Value(true),
        createdAt: now,
        updatedAt: now,
      ),
      mode: InsertMode.insertOrReplace,
    );
  }

  Future<void> saveProfile(BatchProfile profile) async {
    await db.into(db.batchProfileRows).insert(
      BatchProfileRowsCompanion.insert(
        id: profile.id,
        name: profile.name,
        actionsJson: Value(profile.actionsJson),
        kind: Value(profile.kind.name),
        sortOrder: Value(profile.sortOrder),
        isActive: Value(profile.isActive),
        createdAt: profile.createdAt.millisecondsSinceEpoch,
        updatedAt: profile.updatedAt.millisecondsSinceEpoch,
      ),
      mode: InsertMode.insertOrReplace,
    );
  }

  /// Makes [id] the only active profile of its kind.
  Future<void> setActive(BatchProfileKind kind, String id) async {
    await db.transaction(() async {
      await (db.update(db.batchProfileRows)..where((t) => t.kind.equals(kind.name))).write(
        const BatchProfileRowsCompanion(isActive: Value(false)),
      );
      await (db.update(db.batchProfileRows)..where((t) => t.id.equals(id))).write(
        const BatchProfileRowsCompanion(isActive: Value(true)),
      );
    });
  }

  Future<void> deleteProfile(String id) async {
    await (db.delete(db.batchProfileRows)..where((t) => t.id.equals(id))).go();
  }
}
