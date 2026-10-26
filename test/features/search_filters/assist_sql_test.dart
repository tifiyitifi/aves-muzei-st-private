import 'package:aves/features/collection_paging/query/collection_window_predicate.dart';
import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/drift_local_media_db.dart';
import 'package:aves/features/search_filters/model/range_assist_filter.dart';
import 'package:aves/features/search_filters/model/relative_time_filter.dart';
import 'package:aves/features/search_filters/model/search_assist.dart';
import 'package:aves/features/search_filters/model/time_to_now.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/ref/mime_types.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves_model/aves_model.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../helpers/sqlite3_loader.dart';

/// The assist filters must select the same entries through SQL as through the
/// in-memory predicate; otherwise a paged browse and a legacy browse disagree.
void main() {
  setUpAll(() {
    ensureSqlite3Loaded();
    getIt.registerLazySingleton<p.Context>(() => p.Context(style: p.Style.posix));
  });

  tearDownAll(getIt.reset);

  late AppDatabase db;
  late DriftLocalMediaDb service;

  final base = DateTime(2026, 1, 1).millisecondsSinceEpoch;
  const day = Duration.millisecondsPerDay;

  AvesEntry entry(int id, {int? takenMillis, int? contentId, int sizeBytes = 10, int width = 100, int height = 100}) => AvesEntry(
    id: id,
    uri: 'content://$id',
    path: '/a/$id.jpg',
    contentId: contentId ?? id,
    pageId: null,
    sourceMimeType: MimeTypes.jpeg,
    width: width,
    height: height,
    sourceRotationDegrees: 0,
    sizeBytes: sizeBytes,
    sourceTitle: 'title$id',
    dateAddedSecs: 1,
    dateModifiedMillis: 0,
    sourceDateTakenMillis: takenMillis ?? 0,
    durationMillis: 0,
    trashed: false,
    origin: EntryOrigins.mediaStoreContent,
  );

  late List<AvesEntry> entries;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    service = DriftLocalMediaDb(database: db);
    await service.init();
    entries = [
      entry(1, takenMillis: base),
      entry(2, takenMillis: base + day, sizeBytes: 2000, width: 200),
      entry(3, takenMillis: base + 3 * day, sizeBytes: 3000, width: 300, height: 300),
      entry(4),
    ];
    await service.insertEntries(entries.toSet());
  });

  tearDown(() => db.close());

  Future<Set<int>> sqlIds(CollectionFilter filter) async {
    final predicate = predicateForFilters({filter});
    expect(predicate, isNotNull, reason: 'filter must compile to SQL: $filter');
    final window = await service.loadEntryWindow(predicate: predicate!, sort: SortFactor.date, reverse: false, limit: 100, offset: 0);
    return window.map((entry) => entry.id).toSet();
  }

  Future<void> expectSqlMatchesMemory(CollectionFilter filter) async {
    final expected = entries.where(filter.test).map((entry) => entry.id).toSet();
    expect(await sqlIds(filter), expected, reason: '$filter');
  }

  test('a taken date range', () async {
    await expectSqlMatchesMemory(RangeAssistFilter(AssistRangeField.takenDate, min: base + day, max: base + 3 * day));
    await expectSqlMatchesMemory(RangeAssistFilter(AssistRangeField.takenDate, max: base + day));
  });

  test('a size range', () async {
    await expectSqlMatchesMemory(RangeAssistFilter(AssistRangeField.size, min: 2000));
    await expectSqlMatchesMemory(RangeAssistFilter(AssistRangeField.size, max: 10));
  });

  test('a width range', () async {
    await expectSqlMatchesMemory(RangeAssistFilter(AssistRangeField.width, min: 200));
  });

  test('a height range', () async {
    await expectSqlMatchesMemory(RangeAssistFilter(AssistRangeField.height, max: 100));
  });

  test('a content id range', () async {
    await expectSqlMatchesMemory(RangeAssistFilter(AssistRangeField.contentId, min: 2, max: 3));
  });

  test('a reversed range keeps the entries the positive test rejects', () async {
    await expectSqlMatchesMemory(RangeAssistFilter(AssistRangeField.takenDate, min: base + 2 * day, reversed: true));
  });

  test('a relative window uses the filter anchor', () async {
    final filter = RelativeTimeFilter(const TimeToNow(amount: 2, unit: RelativeTimeUnit.day), now: DateTime.fromMillisecondsSinceEpoch(base + 4 * day));
    await expectSqlMatchesMemory(filter);
    await expectSqlMatchesMemory(filter.reverse());
  });

  test('the whole assist set compiles and matches', () async {
    final filters = const SearchAssist(
      size: AssistIntRange(min: 2000),
      dimension: AssistDimension(width: AssistIntRange(min: 200)),
    ).toFilters();
    final predicate = predicateForFilters(filters);
    expect(predicate, isNotNull);
    final window = await service.loadEntryWindow(predicate: predicate!, sort: SortFactor.date, reverse: false, limit: 100, offset: 0);
    final expected = entries.where((entry) => filters.every((filter) => filter.test(entry))).map((entry) => entry.id).toSet();
    expect(window.map((entry) => entry.id).toSet(), expected);
  });
}
