import 'package:aves/features/album_contents_move/model/album_contents_move_plan.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../common.dart';

void main() {
  const sourceA = '/storage/emulated/0/Pictures/A';
  const sourceB = '/storage/emulated/0/Pictures/B';
  const destination = '/storage/emulated/0/Pictures/Destination';

  setUpAll(setUpAllServices);
  tearDownAll(tearDownAllServices);

  AvesEntry entry(int id, String directory) => AvesEntry(
    id: id,
    uri: 'content://$directory/$id',
    path: '$directory/$id.jpg',
    contentId: id,
    pageId: null,
    sourceMimeType: 'image/jpeg',
    width: 10,
    height: 20,
    sourceRotationDegrees: 0,
    sizeBytes: 5,
    sourceTitle: '$id',
    dateAddedSecs: 1,
    dateModifiedMillis: 2,
    sourceDateTakenMillis: 3,
    durationMillis: 0,
    trashed: false,
    origin: EntryOrigins.mediaStoreContent,
  );

  test('moves visible entries from every selected album into the destination', () {
    final plan = AlbumContentsMovePlan.resolve(
      sourceAlbums: {sourceA, sourceB},
      removableSourceAlbums: {sourceA, sourceB},
      destination: destination,
      entries: {entry(1, sourceA), entry(2, sourceA), entry(3, sourceB)},
    );

    expect(plan.isValid, isTrue);
    expect(plan.entryCount, 3);
    expect(plan.entriesByDestination.keys, {destination});
    expect(plan.entriesByDestination[destination]?.length, 3);
    expect(plan.movedSourceAlbums, {sourceA, sourceB});
    expect(plan.sourceAlbumsToClean, {sourceA, sourceB});
  });

  test('merges the other albums when the destination is also a source', () {
    final plan = AlbumContentsMovePlan.resolve(
      sourceAlbums: {sourceA, sourceB},
      removableSourceAlbums: {sourceA, sourceB},
      destination: sourceA,
      entries: {entry(1, sourceA), entry(2, sourceB)},
    );

    expect(plan.isValid, isTrue);
    expect(plan.entryCount, 1);
    expect(plan.entriesByDestination[sourceA]?.single.uri, 'content://$sourceB/2');
    expect(plan.movedSourceAlbums, {sourceB});
    // The destination album is never a cleanup candidate.
    expect(plan.sourceAlbumsToClean, {sourceB});
  });

  test('rejects a destination inside one of the selected albums', () {
    final plan = AlbumContentsMovePlan.resolve(
      sourceAlbums: {sourceA, sourceB},
      removableSourceAlbums: {sourceA, sourceB},
      destination: '$sourceA/Child',
      entries: {entry(1, sourceA), entry(2, sourceB)},
    );

    expect(plan.isValid, isFalse);
    expect(plan.error, AlbumContentsMoveError.destinationInsideSource);
  });

  test('rejects the only selected album as the destination', () {
    final plan = AlbumContentsMovePlan.resolve(
      sourceAlbums: {sourceA},
      removableSourceAlbums: {sourceA},
      destination: sourceA,
      entries: {entry(1, sourceA)},
    );

    expect(plan.isValid, isFalse);
    expect(plan.error, AlbumContentsMoveError.destinationIsOnlySource);
  });

  test('rejects a move without visible entries', () {
    final plan = AlbumContentsMovePlan.resolve(
      sourceAlbums: {sourceA, sourceB},
      removableSourceAlbums: {sourceA, sourceB},
      destination: destination,
      entries: {entry(1, '/storage/emulated/0/Pictures/Other')},
    );

    expect(plan.isValid, isFalse);
    expect(plan.error, AlbumContentsMoveError.noEntries);
  });

  test('only offers moved, removable albums for cleanup', () {
    final plan = AlbumContentsMovePlan.resolve(
      sourceAlbums: {sourceA, sourceB},
      removableSourceAlbums: {sourceA},
      destination: destination,
      entries: {entry(1, sourceA), entry(2, sourceB)},
    );

    expect(plan.isValid, isTrue);
    expect(plan.movedSourceAlbums, {sourceA, sourceB});
    expect(plan.sourceAlbumsToClean, {sourceA});
  });
}
