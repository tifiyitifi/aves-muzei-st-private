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

  AvesEntry entry(int id, String mimeType, {int? takenMillis}) => AvesEntry(
        id: id,
        uri: 'content://$id',
        path: '/a/$id',
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

  Future<Map<String, VisibleRangeCandidateStats>> load(Iterable<Set<CollectionFilter>> filterSets) {
    return VisibleRangeCandidateStatsLoader.load(
      filterSets,
      hidden: const {},
      lockedVaultDirs: const {},
      database: service,
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
}
