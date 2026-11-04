import 'package:aves/features/album_contents_move/model/album_contents_move_plan.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../common.dart';

void main() {
  const sourceA = '/storage/emulated/0/Pictures/A';
  const sourceB = '/storage/emulated/0/Pictures/B';
  const destination = '/storage/emulated/0/Pictures/Destination';

  setUpAll(setUpAllServices);
  tearDownAll(tearDownAllServices);

  test('reports what travels from every selected album', () {
    final plan = AlbumContentsMovePlan.resolve(
      sourceAlbums: {sourceA, sourceB},
      destination: destination,
      entryCount: 3,
    );

    expect(plan.isValid, isTrue);
    expect(plan.entryCount, 3);
    expect(plan.destination, destination);
    expect(plan.movingAlbums, {sourceA, sourceB});
  });

  test('merges the other albums when the destination is also a source', () {
    final plan = AlbumContentsMovePlan.resolve(
      sourceAlbums: {sourceA, sourceB},
      destination: sourceA,
      // The caller counts the entries of every source album but the destination.
      entryCount: 1,
    );

    expect(plan.isValid, isTrue);
    expect(plan.entryCount, 1);
    expect(plan.movingAlbums, {sourceB});
  });

  test('rejects a destination inside one of the selected albums', () {
    final plan = AlbumContentsMovePlan.resolve(
      sourceAlbums: {sourceA, sourceB},
      destination: '$sourceA/Child',
      entryCount: 2,
    );

    expect(plan.isValid, isFalse);
    expect(plan.error, AlbumContentsMoveError.destinationInsideSource);
  });

  test('rejects the only selected album as the destination', () {
    final plan = AlbumContentsMovePlan.resolve(
      sourceAlbums: {sourceA},
      destination: sourceA,
      entryCount: 0,
    );

    expect(plan.isValid, isFalse);
    expect(plan.error, AlbumContentsMoveError.destinationIsOnlySource);
  });

  test('rejects a move without visible entries', () {
    final plan = AlbumContentsMovePlan.resolve(
      sourceAlbums: {sourceA, sourceB},
      destination: destination,
      entryCount: 0,
    );

    expect(plan.isValid, isFalse);
    expect(plan.error, AlbumContentsMoveError.noEntries);
  });

  test('offers only moved, removable albums for cleanup', () {
    final plan = AlbumContentsMovePlan.resolve(
      sourceAlbums: {sourceA, sourceB},
      destination: destination,
      entryCount: 2,
    );

    final candidates = plan.cleanupCandidates(
      movedSourceAlbums: {sourceA, sourceB},
      removableSourceAlbums: {sourceA},
    );

    expect(candidates, {sourceA});
  });

  test('never offers the destination album for cleanup', () {
    final plan = AlbumContentsMovePlan.resolve(
      sourceAlbums: {sourceA, sourceB},
      destination: sourceA,
      entryCount: 1,
    );

    final candidates = plan.cleanupCandidates(
      movedSourceAlbums: {sourceB},
      removableSourceAlbums: {sourceA, sourceB},
    );

    expect(candidates, {sourceB});
  });

  test('keeps an album this move took nothing from', () {
    final plan = AlbumContentsMovePlan.resolve(
      sourceAlbums: {sourceA, sourceB},
      destination: destination,
      entryCount: 2,
    );

    final candidates = plan.cleanupCandidates(
      movedSourceAlbums: {sourceA},
      removableSourceAlbums: {sourceA, sourceB},
    );

    expect(candidates, {sourceA});
  });

  test('offers nothing for an invalid plan', () {
    final plan = AlbumContentsMovePlan.resolve(
      sourceAlbums: {sourceA},
      destination: sourceA,
      entryCount: 0,
    );

    expect(
      plan.cleanupCandidates(movedSourceAlbums: {sourceA}, removableSourceAlbums: {sourceA}),
      isEmpty,
    );
  });
}
