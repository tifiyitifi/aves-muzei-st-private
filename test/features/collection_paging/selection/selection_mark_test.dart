import 'package:aves/features/collection_paging/query/collection_window_predicate.dart';
import 'package:aves/features/collection_paging/selection/declared_entry_feed.dart';
import 'package:aves/features/collection_paging/selection/selection_mark.dart';
import 'package:aves/features/collection_paging/selection/selection_trait.dart';
import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/drift_local_media_db.dart';
import 'package:aves/model/db/db.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:aves/model/filters/covered/tag.dart';
import 'package:aves/model/filters/rating.dart';
import 'package:aves/model/metadata/catalog.dart';
import 'package:aves/model/source/media_store_source.dart';
import 'package:aves/services/common/services.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../../../common.dart';
import '../../../helpers/sqlite3_loader.dart';

/// A marked whole-view selection: the manual taps, the ordered trait history and
/// the view's own scope, all answering one question through one predicate.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    ensureSqlite3Loaded();
    SharedPreferencesStorePlatform.instance = InMemorySharedPreferencesStore.empty();
    await setUpAllServices();
  });

  late AppDatabase db;
  late DriftLocalMediaDb driftDb;
  late MediaStoreSource source;

  setUpAll(() async {
    db = AppDatabase(NativeDatabase.memory());
    driftDb = DriftLocalMediaDb(database: db);
    await driftDb.init();
    getIt.unregister<LocalMediaDb>();
    getIt.registerLazySingleton<LocalMediaDb>(() => driftDb);
  });

  tearDownAll(() async {
    await tearDownAllServices();
    await db.close();
  });

  setUp(() async {
    await driftDb.clearEntries();
    await driftDb.clearCatalogMetadata();
    await driftDb.clearDates();
    await driftDb.clearAddresses();
    await driftDb.clearTrashDetails();
    source = MediaStoreSource();
    source.canAnalyze = false;
  });

  tearDown(() async {
    await setUpServices();
  });

  /// One row carrying the catalog metadata its traits read (tags, rating), so
  /// the in-memory test and the SQL fragment are compared on the same entry.
  AvesEntry entry(int id, {String dir = '/album', String? tags, int rating = 0}) {
    final entry = AvesEntry(
      id: id,
      uri: 'content://$id',
      path: '$dir/$id.jpg',
      contentId: 100 + id,
      pageId: null,
      sourceMimeType: 'image/jpeg',
      width: 10,
      height: 20,
      sourceRotationDegrees: 0,
      sizeBytes: 5,
      sourceTitle: 'title$id',
      dateAddedSecs: 1,
      dateModifiedMillis: 2,
      sourceDateTakenMillis: 0,
      durationMillis: 0,
      trashed: false,
      origin: EntryOrigins.mediaStoreContent,
    );
    entry.catalogMetadata = CatalogMetadata(id: id, xmpSubjects: tags, rating: rating);
    return entry;
  }

  /// Inserts the rows and the metadata their traits compile against.
  Future<void> seed(Set<AvesEntry> entries) async {
    await driftDb.insertEntries(entries);
    await driftDb.saveCatalogMetadata({for (final entry in entries) entry.catalogMetadata!});
  }

  SelectionTrait albumTrait(String directory) => SelectionTrait.fromFilter(StoredAlbumFilter(directory, null))!;

  SelectionTrait tagTrait(String tag) => SelectionTrait.fromFilter(TagFilter(tag))!;

  /// A mark over the whole (live) library, seeded like the lens seeds one.
  Future<CollectionSelectionMark> newMark() async {
    const scope = CollectionWindowPredicate();
    final total = await driftDb.countEntries(scope);
    return CollectionSelectionMark(
      scope: const SelectionScope(tiles: scope, entries: scope),
      count: total,
      expandedCount: total,
    );
  }

  /// Lets the mark's own recount land, then reports what it says.
  Future<int> settledCount(CollectionSelectionMark mark) async {
    await mark.recount();
    return mark.count;
  }

  group('CollectionSelectionMark', () {
    test('the last trait op covering a row decides, across different traits', () async {
      await seed({
        entry(1, tags: 'x'),
        entry(2, tags: 'x'),
        entry(3, dir: '/b'),
      });
      final mark = await newMark();
      expect(await settledCount(mark), 3);

      // Deselecting the album takes its rows out, the other album included in.
      mark.deselectTrait(albumTrait('/album'), label: 'album');
      expect(await settledCount(mark), 1);
      expect(mark.isMarked(entry(1, tags: 'x')), isFalse);
      expect(mark.isMarked(entry(3, dir: '/b')), isTrue);

      // Selecting the tag afterwards wins on the overlap: the later op decides.
      mark.selectTrait(tagTrait('x'), label: 'tag');
      expect(await settledCount(mark), 3);
      expect(mark.isMarked(entry(1, tags: 'x')), isTrue);
      expect(mark.isMarked(entry(2, tags: 'x')), isTrue);
    });

    test('the reverse order leaves the overlap deselected', () async {
      await seed({
        entry(1, tags: 'x'),
        entry(2, tags: 'x'),
        entry(3, dir: '/b'),
      });
      final mark = await newMark();

      mark.selectTrait(tagTrait('x'), label: 'tag');
      mark.deselectTrait(albumTrait('/album'), label: 'album');
      // The album op came last, so it wins where the two overlap.
      expect(await settledCount(mark), 1);
      expect(mark.isMarked(entry(1, tags: 'x')), isFalse);
      expect(mark.isMarked(entry(3, dir: '/b')), isTrue);
    });

    test('a manual tap pierces every trait, and no later op can undo it', () async {
      await seed({
        entry(1, tags: 'x'),
        entry(2, tags: 'x'),
        entry(3, dir: '/b'),
      });
      final mark = await newMark();

      mark.deselectTrait(albumTrait('/album'), label: 'album');
      mark.mark([entry(1, tags: 'x')]);
      expect(mark.isMarked(entry(1, tags: 'x')), isTrue);
      expect(await settledCount(mark), 2);

      // The manual layer is not ordered: a trait added after the tap still
      // cannot take the row the user tapped back.
      mark.deselectTrait(albumTrait('/album'), label: 'album');
      expect(mark.isMarked(entry(1, tags: 'x')), isTrue);
      expect(await settledCount(mark), 2);
    });

    test('a manual drop wins over a trait that selects the row', () async {
      await seed({
        entry(1, tags: 'x'),
        entry(2, tags: 'x'),
        entry(3, dir: '/b'),
      });
      final mark = await newMark();

      mark.selectTrait(tagTrait('x'), label: 'tag');
      mark.unmark([entry(1, tags: 'x')]);
      expect(mark.isMarked(entry(1, tags: 'x')), isFalse);
      expect(await settledCount(mark), 2);

      mark.selectTrait(tagTrait('x'), label: 'tag');
      expect(mark.isMarked(entry(1, tags: 'x')), isFalse);
      expect(await settledCount(mark), 2);
    });

    test('a trait op never touches the manual layers', () async {
      await seed({
        entry(1, tags: 'x'),
        entry(2, tags: 'x'),
        entry(3, dir: '/b'),
      });
      final mark = await newMark();

      mark.mark([entry(1, tags: 'x')]);
      mark.unmark([entry(2, tags: 'x')]);
      mark.deselectTrait(albumTrait('/album'), label: 'album');
      mark.selectTrait(albumTrait('/album'), label: 'album');

      expect(mark.isMarked(entry(1, tags: 'x')), isTrue);
      expect(mark.isMarked(entry(2, tags: 'x')), isFalse);
      expect(await settledCount(mark), 2);
    });

    test('a reversed filter trait is the complement of its own test', () async {
      await seed({
        entry(1, rating: 5),
        entry(2),
      });
      final mark = await newMark();

      mark.deselectTrait(SelectionTrait.fromFilter(RatingFilter(5))!, label: 'five');
      expect(await settledCount(mark), 1);

      // The reversed trait covers exactly the row the positive one left.
      mark.deselectTrait(SelectionTrait.fromFilter(RatingFilter(5, reversed: true))!, label: 'not five');
      expect(await settledCount(mark), 0);

      mark.selectTrait(SelectionTrait.fromFilter(RatingFilter(5))!, label: 'five');
      expect(await settledCount(mark), 1);
      expect(mark.isMarked(entry(1, rating: 5)), isTrue);
    });

    test('the count, the walk and the highlight answer the same rows', () async {
      final rows = {
        entry(1, tags: 'x'),
        entry(2, tags: 'x'),
        entry(3, tags: 'y'),
        entry(4, dir: '/b'),
        entry(5, dir: '/b', tags: 'x'),
      };
      await seed(rows);
      final mark = await newMark();

      mark.deselectTrait(albumTrait('/album'), label: 'album');
      // A manual row inside the deselected album: the walk must still yield it.
      mark.mark([entry(1, tags: 'x')]);
      await mark.recount();

      final feed = DeclaredEntryFeed(
        mark: mark,
        tilePredicate: mark.tilePredicate,
        tileCount: mark.walkCount,
        count: mark.expandedCount,
        stackEntries: false,
      );
      final walked = <int>[];
      await for (final batch in feed.batches()) {
        for (final row in batch) {
          expect(mark.isMarked(row), isTrue, reason: 'a walked row must be highlighted');
          walked.add(row.id);
        }
      }

      final highlighted = [for (final row in rows) if (mark.isMarked(row)) row.id];
      expect(walked..sort(), highlighted..sort());
      expect(walked, [1, 4, 5]);
      expect(mark.count, await driftDb.countEntries(mark.tilePredicate));
      expect(walked.length, mark.count);
    });

    test('clearing the mark drops the traits and the manual layers', () async {
      await seed({
        entry(1, tags: 'x'),
        entry(2, tags: 'x'),
        entry(3, dir: '/b'),
      });
      final mark = await newMark();

      mark.deselectTrait(albumTrait('/album'), label: 'album');
      mark.unmark([entry(3, dir: '/b')]);
      mark.clear();

      expect(mark.ops, isEmpty);
      expect(mark.isMarked(entry(1, tags: 'x')), isTrue);
      expect(mark.isMarked(entry(3, dir: '/b')), isTrue);
      expect(await settledCount(mark), 3);
    });
  });
}
