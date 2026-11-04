import 'package:aves/features/album_contents_transfer/model/album_contents_transfer_plan.dart';
import 'package:aves_model/aves_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../common.dart';

void main() {
  const sourceA = '/storage/emulated/0/Pictures/A';
  const sourceB = '/storage/emulated/0/Pictures/B';
  const destination = '/storage/emulated/0/Pictures/Destination';

  setUpAll(setUpAllServices);
  tearDownAll(tearDownAllServices);

  AlbumContentsTransferPlan movePlan({
    required Set<String> sourceAlbums,
    required String? destination,
    required int entryCount,
  }) {
    return AlbumContentsTransferPlan.resolve(
      moveType: MoveType.move,
      sourceAlbums: sourceAlbums,
      destination: destination,
      entryCount: entryCount,
    );
  }

  AlbumContentsTransferPlan copyPlan({
    required Set<String> sourceAlbums,
    required String? destination,
    required int entryCount,
  }) {
    return AlbumContentsTransferPlan.resolve(
      moveType: MoveType.copy,
      sourceAlbums: sourceAlbums,
      destination: destination,
      entryCount: entryCount,
    );
  }

  test('reports what travels from every selected album', () {
    final plan = movePlan(sourceAlbums: {sourceA, sourceB}, destination: destination, entryCount: 3);

    expect(plan.isValid, isTrue);
    expect(plan.entryCount, 3);
    expect(plan.destination, destination);
    expect(plan.movingAlbums, {sourceA, sourceB});
    expect(plan.copies, isFalse);
  });

  test('merges the other albums when the destination is also a source', () {
    final plan = movePlan(
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
    final plan = movePlan(
      sourceAlbums: {sourceA, sourceB},
      destination: '$sourceA/Child',
      entryCount: 2,
    );

    expect(plan.isValid, isFalse);
    expect(plan.error, AlbumContentsTransferError.destinationInsideSource);
  });

  test('rejects the only selected album as the destination', () {
    final plan = movePlan(sourceAlbums: {sourceA}, destination: sourceA, entryCount: 0);

    expect(plan.isValid, isFalse);
    expect(plan.error, AlbumContentsTransferError.destinationIsOnlySource);
  });

  test('rejects a transfer without visible entries', () {
    final plan = movePlan(sourceAlbums: {sourceA, sourceB}, destination: destination, entryCount: 0);

    expect(plan.isValid, isFalse);
    expect(plan.error, AlbumContentsTransferError.noEntries);
  });

  test('offers only moved, removable albums for cleanup', () {
    final plan = movePlan(sourceAlbums: {sourceA, sourceB}, destination: destination, entryCount: 2);

    final candidates = plan.cleanupCandidates(
      movedSourceAlbums: {sourceA, sourceB},
      removableSourceAlbums: {sourceA},
    );

    expect(candidates, {sourceA});
  });

  test('never offers the destination album for cleanup', () {
    final plan = movePlan(sourceAlbums: {sourceA, sourceB}, destination: sourceA, entryCount: 1);

    final candidates = plan.cleanupCandidates(
      movedSourceAlbums: {sourceB},
      removableSourceAlbums: {sourceA, sourceB},
    );

    expect(candidates, {sourceB});
  });

  test('keeps an album this move took nothing from', () {
    final plan = movePlan(sourceAlbums: {sourceA, sourceB}, destination: destination, entryCount: 2);

    final candidates = plan.cleanupCandidates(
      movedSourceAlbums: {sourceA},
      removableSourceAlbums: {sourceA, sourceB},
    );

    expect(candidates, {sourceA});
  });

  test('offers nothing for an invalid plan', () {
    final plan = movePlan(sourceAlbums: {sourceA}, destination: sourceA, entryCount: 0);

    expect(
      plan.cleanupCandidates(movedSourceAlbums: {sourceA}, removableSourceAlbums: {sourceA}),
      isEmpty,
    );
  });

  test('plans a copy like a move, minus the folder cleanup', () {
    final plan = copyPlan(sourceAlbums: {sourceA, sourceB}, destination: destination, entryCount: 4);

    expect(plan.isValid, isTrue);
    expect(plan.copies, isTrue);
    expect(plan.entryCount, 4);
    expect(plan.movingAlbums, {sourceA, sourceB});
    // A copy leaves every source album in place, so nothing may be removed.
    expect(
      plan.cleanupCandidates(movedSourceAlbums: {sourceA, sourceB}, removableSourceAlbums: {sourceA, sourceB}),
      isEmpty,
    );
  });

  test('rejects a copy into the only selected album', () {
    final plan = copyPlan(sourceAlbums: {sourceA}, destination: sourceA, entryCount: 2);

    expect(plan.isValid, isFalse);
    expect(plan.error, AlbumContentsTransferError.destinationIsOnlySource);
  });
}
