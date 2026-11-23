import 'package:flutter_test/flutter_test.dart';

import '../../helpers/sqlite3_loader.dart';
import 'legacy_database.dart';

/// Schema v13 -> v14 folds a group's lock range into its condition pool.
void main() {
  setUpAll(ensureSqlite3Loaded);

  test('a v13 lock range merges into the home pool', () async {
    final db = await openDatabaseAt(13, (seed) async {
      await seed.customStatement('ALTER TABLE visible_ranges DROP COLUMN baseSurfaces');
      await seed.customStatement('ALTER TABLE visible_range_rules DROP COLUMN surfaces');
      await seed.customStatement('ALTER TABLE wallpaper_groups DROP COLUMN lockRangeSeeded');
      await seed.customStatement("INSERT INTO wallpaper_groups (id, createdAt, updatedAt) VALUES ('g1', 1, 2)");
      // The home and lock ranges share their base, so the pool marks it for both
      // surfaces. The identical rules merge the same way.
      await seed.customStatement(
        'INSERT INTO visible_ranges (id, scope, ownerId, baseFilters, baseActive, createdAt, updatedAt) VALUES '
        "('g1', 'wallpaper', 'g1', '[{\"type\":\"favourite\"}]', 1, 1, 2), "
        "('g1.lock.range', 'wallpaper', 'g1', '[{\"type\":\"favourite\"}]', 1, 1, 2)",
      );
      await seed.customStatement(
        'INSERT INTO visible_range_rules (id, rangeId, kind, position, filters, active) VALUES '
        "('r-home', 'g1', 'restriction', 0, '[{\"type\":\"favourite\"}]', 1), "
        "('r-lock', 'g1.lock.range', 'restriction', 0, '[{\"type\":\"favourite\"}]', 1)",
      );
    });

    // The pool row is the home range, marked for both surfaces (home 1 | lock 2).
    final base = await db.customSelect("SELECT baseSurfaces FROM visible_ranges WHERE id = 'g1'").getSingle();
    expect(base.data['baseSurfaces'], 3);

    // v19 adds a `source` rule for the base; the folded restriction is still one.
    final rules = await db.customSelect("SELECT id, surfaces FROM visible_range_rules WHERE kind <> 'source' ORDER BY id").get();
    expect(rules, hasLength(1), reason: 'the identical lock rule folds into the home one');
    expect(rules.single.data['id'], 'r-home');
    expect(rules.single.data['surfaces'], 3);

    final lockRange = await db.customSelect("SELECT id FROM visible_ranges WHERE id = 'g1.lock.range'").get();
    expect(lockRange, isEmpty, reason: 'the lock range is folded and deleted');

    final seeded = await db.customSelect("SELECT lockRangeSeeded FROM wallpaper_groups WHERE id = 'g1'").getSingle();
    expect(seeded.data['lockRangeSeeded'], 1, reason: 'the lock surface was seeded once');
  });
}
