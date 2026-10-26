import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/visible_range/db/visible_range_store.dart';
import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/model/filters/favourite.dart';
import 'package:aves/model/filters/mime.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/sqlite3_loader.dart';

/// Persistence round-trips for visible ranges, rules, presets, state and
/// sessions, including explicit cleanup (foreign keys are off).
void main() {
  setUpAll(ensureSqlite3Loaded);

  late AppDatabase db;
  late VisibleRangeStore store;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    store = VisibleRangeStore(db);
  });

  tearDown(() => db.close());

  final image = MimeFilter.image;
  const favourite = FavouriteFilter.instance;

  VisibleRange makeRange({String id = 'gallery', VisibleRangePermissions permissions = VisibleRangePermissions.readOnly}) => VisibleRange(
        id: id,
        scope: VisibleRangeScope.gallery,
        ownerId: VisibleRange.galleryOwnerId,
        baseName: 'visibleRangePresetImage',
        basePresetId: 'builtin.image',
        baseFilters: {image},
        order: VisibleRangeOrder.unionFirst,
        locked: true,
        permissions: permissions,
        createdAt: 10,
        updatedAt: 20,
      );

  test('round-trips a range and its rules', () async {
    final range = makeRange();
    await store.saveRange(range);
    await store.saveRule(VisibleRangeRule(id: 'r1', rangeId: range.id, kind: VisibleRangeRuleKind.restriction, position: 0, filters: {favourite}));
    await store.saveRule(VisibleRangeRule(
      id: 'r2',
      rangeId: range.id,
      kind: VisibleRangeRuleKind.supplement,
      position: 1,
      label: 'mine',
      description: 'pinned on a rainy day',
      filters: {image},
      active: false,
    ));

    final loaded = await store.loadRange(scope: VisibleRangeScope.gallery, ownerId: VisibleRange.galleryOwnerId);
    expect(loaded, isNotNull);
    expect(loaded!.baseFilters, {image});
    expect(loaded.basePresetId, 'builtin.image');
    expect(loaded.order, VisibleRangeOrder.unionFirst);
    expect(loaded.locked, isTrue);
    expect(loaded.permissions.delete, isFalse);
    expect(loaded.permissions.share, isTrue);
    expect(loaded.rules.map((r) => r.id), ['r1', 'r2']);
    expect(loaded.rules[1].label, 'mine');
    expect(loaded.rules[1].description, 'pinned on a rainy day');
    expect(loaded.rules[0].description, isEmpty);
    expect(loaded.rules[1].active, isFalse);
  });

  test('stores edited permissions', () async {
    await store.saveRange(makeRange(permissions: VisibleRangePermissions.full));
    final loaded = await store.loadRange(scope: VisibleRangeScope.gallery, ownerId: VisibleRange.galleryOwnerId);
    expect(loaded!.permissions.vault, isTrue);
    expect(loaded.permissions.edit, isTrue);
  });

  test('an unlocked range drops stale permissions', () async {
    await store.saveRange(makeRange(permissions: VisibleRangePermissions.full));
    await store.saveRange(makeRange().copyWith(locked: false));
    final loaded = await store.loadRange(scope: VisibleRangeScope.gallery, ownerId: VisibleRange.galleryOwnerId);
    expect(loaded!.permissions, VisibleRangePermissions.readOnly);
  });

  test('replaceRules replaces the whole set', () async {
    final range = makeRange();
    await store.saveRange(range);
    await store.saveRule(VisibleRangeRule(id: 'r1', rangeId: range.id, kind: VisibleRangeRuleKind.restriction, filters: {image}));
    await store.replaceRules(range.id, [
      VisibleRangeRule(id: 'r2', rangeId: range.id, kind: VisibleRangeRuleKind.supplement, filters: {favourite}),
    ]);
    expect((await store.loadRules(range.id)).map((r) => r.id), ['r2']);
  });

  test('deleting a range clears its rules and sessions', () async {
    final range = makeRange();
    await store.saveRange(range);
    await store.saveRule(VisibleRangeRule(id: 'r1', rangeId: range.id, kind: VisibleRangeRuleKind.restriction, filters: {image}));
    await store.saveSession(
      VisibleRangeSession(
        id: 's1',
        rangeId: range.id,
        ruleId: 'r1',
        kind: VisibleRangeRuleKind.restriction,
        mode: VisibleRangeActivationMode.override,
        initialFilters: {image},
        finalFilters: {favourite},
        createdAt: 1,
      ),
    );
    await store.deleteRange(range.id);
    expect(await store.loadRange(scope: VisibleRangeScope.gallery, ownerId: VisibleRange.galleryOwnerId), isNull);
    expect(await store.loadRules(range.id), isEmpty);
    expect(await store.loadSessions(), isEmpty);
  });

  test('presets and state round-trip', () async {
    await store.savePreset(const VisibleRangePreset(id: 'builtin.image', name: 'visibleRangePresetImage', builtin: true));
    await store.savePreset(VisibleRangePreset(id: 'user.1', name: 'Mine', description: 'my note', filters: {favourite}, position: 1));
    final presets = await store.loadPresets();
    expect(presets.map((p) => p.id), ['builtin.image', 'user.1']);
    expect(presets[1].filters, {favourite});
    expect(presets[1].description, 'my note');
    expect(presets[0].description, isEmpty);

    await store.writeState(VisibleRangeStore.keySeeded, '1');
    expect(await store.readState(VisibleRangeStore.keySeeded), '1');
    await store.writeState(VisibleRangeStore.keySeeded, null);
    expect(await store.readState(VisibleRangeStore.keySeeded), isNull);
  });

  test('sessions can be filtered by range and cleared', () async {
    VisibleRangeSession session(String id, String rangeId) => VisibleRangeSession(
          id: id,
          rangeId: rangeId,
          ruleId: 'r1',
          kind: VisibleRangeRuleKind.restriction,
          mode: VisibleRangeActivationMode.append,
          initialFilters: {image},
          finalFilters: {favourite},
          createdAt: 1,
        );
    await store.saveSession(session('s1', 'gallery'));
    await store.saveSession(session('s2', 'other'));
    expect((await store.loadSessions(rangeId: 'gallery')).map((s) => s.id), ['s1']);
    await store.clearSessions();
    expect(await store.loadSessions(), isEmpty);
  });
}
