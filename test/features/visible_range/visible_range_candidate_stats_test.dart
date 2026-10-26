import 'dart:io';

import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/drift_local_media_db.dart';
import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/features/visible_range/services/visible_range_candidate_stats.dart';
import 'package:aves/locale/aves_locale.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/filters/mime.dart';
import 'package:aves/model/filters/query.dart';
import 'package:aves/ref/mime_types.dart';
import 'package:aves/services/common/services.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../helpers/sqlite3_loader.dart';

/// Candidate previews: one count and one cover per distinct filter set, and an
/// unusable filter reports null instead of falling back to a library scan.
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

  AvesEntry entry(int id, String mimeType, {int? takenMillis, String? path}) => AvesEntry(
        id: id,
        uri: 'content://$id',
        path: path ?? '/a/$id',
        contentId: id,
        pageId: null,
        sourceMimeType: mimeType,
        width: 100,
        height: 100,
        sourceRotationDegrees: 0,
        sizeBytes: 10,
        sourceTitle: 'title$id',
        dateAddedSecs: 1,
        dateModifiedMillis: 0,
        sourceDateTakenMillis: takenMillis ?? 0,
        durationMillis: 0,
        trashed: false,
        origin: EntryOrigins.mediaStoreContent,
      );

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    service = DriftLocalMediaDb(database: db);
    await service.init();
    await service.insertEntries({
      entry(1, MimeTypes.jpeg, takenMillis: base),
      entry(2, MimeTypes.jpeg, takenMillis: base + day),
      entry(3, MimeTypes.mp4, takenMillis: base + 2 * day),
    });
  });

  tearDown(() => db.close());

  /// Tests use made-up paths, so cover validation is off unless a test opts in.
  Future<Map<String, VisibleRangeCandidateStats>> load(
    Iterable<Set<CollectionFilter>> filterSets, {
    bool validateCovers = false,
  }) {
    return VisibleRangeCandidateStatsLoader.load(
      filterSets,
      hidden: const {},
      lockedVaultDirs: const {},
      database: service,
      isCoverUsable: validateCovers ? null : (_) => true,
    );
  }

  test('counts and covers each distinct filter set once', () async {
    final stats = await load([
      <CollectionFilter>{MimeFilter.image},
      <CollectionFilter>{MimeFilter.video},
      <CollectionFilter>{},
      <CollectionFilter>{MimeFilter.image},
    ]);

    final image = stats[filterFingerprint(<CollectionFilter>{MimeFilter.image})]!;
    final video = stats[filterFingerprint(<CollectionFilter>{MimeFilter.video})]!;
    final all = stats[filterFingerprint(<CollectionFilter>{})]!;

    expect(image.count, 2);
    expect(video.count, 1);
    expect(all.count, 3);
    // The newest entry is the cover.
    expect(image.cover?.id, 2);
    expect(video.cover?.id, 3);
    expect(all.cover?.id, 3);
  });

  test('a single candidate reports its own count', () async {
    final stats = await load([
      <CollectionFilter>{MimeFilter.video},
    ]);
    expect(stats.values.single.count, 1);
    expect(stats.values.single.cover?.id, 3);
  });

  test('an SQL-inexpressible filter reports no count', () async {
    final stats = await load([
      <CollectionFilter>{QueryFilter('/regex/', ACalendar.gregorian)},
    ]);
    expect(stats.values.single.count, isNull);
    expect(stats.values.single.cover, isNull);
  });

  test('a hidden filter is excluded from the preview', () async {
    final stats = await VisibleRangeCandidateStatsLoader.load(
      [
        <CollectionFilter>{MimeFilter.image},
      ],
      hidden: {MimeFilter.image},
      lockedVaultDirs: const {},
      database: service,
    );
    expect(stats.values.single.count, 0);
  });

  test('a cover whose file is gone is skipped in favour of the newest existing one', () async {
    final dir = await Directory.systemTemp.createTemp('aves_visible_range_stats');
    addTearDown(() => dir.delete(recursive: true));
    final existing = File(p.join(dir.path, 'existing.jpg'))..writeAsBytesSync([1, 2, 3]);
    await service.insertEntries({
      entry(4, MimeTypes.jpeg, takenMillis: base + 3 * day),
      entry(5, MimeTypes.jpeg, takenMillis: base + 4 * day, path: existing.path),
      // Newest, but its file no longer exists (deleted since the last scan).
      entry(6, MimeTypes.jpeg, takenMillis: base + 5 * day),
    });

    final stats = await load([
      <CollectionFilter>{MimeFilter.image},
    ], validateCovers: true);
    final image = stats.values.single;
    expect(image.count, 5);
    expect(image.cover?.id, 5);
  });

  test('reports no cover when every candidate file is gone', () async {
    final stats = await load([
      <CollectionFilter>{MimeFilter.image},
    ], validateCovers: true);
    expect(stats.values.single.count, 2);
    expect(stats.values.single.cover, isNull);
  });

  test('an unrestricted range previews the whole library with its newest cover', () async {
    // The footer's gallery chip resolves an unrestricted range to no filter at
    // all, which still has to report a count and a cover.
    final stats = await load([const <CollectionFilter>{}]);
    final all = stats.values.single;
    expect(all.count, 3);
    expect(all.cover?.id, 3);
  });
}
