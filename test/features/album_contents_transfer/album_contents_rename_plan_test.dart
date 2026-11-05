import 'package:aves/features/album_contents_transfer/model/album_contents_rename_plan.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../common.dart';

/// The filesystem side of an album rename: the destination derives from the
/// album's parent, and a no-op or unusable name is answered before any move.
void main() {
  const album = '/storage/emulated/0/Pictures/Holidays';

  setUpAll(setUpAllServices);
  tearDownAll(tearDownAllServices);

  test('places the renamed album next to the original', () {
    final plan = AlbumContentsRenamePlan.resolve(album: album, newName: 'Trips');

    expect(plan.isValid, isTrue);
    expect(plan.isNoOp, isFalse);
    expect(plan.destination, '/storage/emulated/0/Pictures/Trips');
  });

  test('treats the current name as a no-op', () {
    final plan = AlbumContentsRenamePlan.resolve(album: album, newName: 'Holidays');

    expect(plan.isValid, isFalse);
    expect(plan.isNoOp, isTrue);
    expect(plan.error, AlbumContentsRenameError.sameName);
  });

  test('rejects an empty name', () {
    final plan = AlbumContentsRenamePlan.resolve(album: album, newName: '');

    expect(plan.isValid, isFalse);
    expect(plan.isNoOp, isFalse);
    expect(plan.error, AlbumContentsRenameError.emptyName);
  });

  test('rejects a rename without an album', () {
    final plan = AlbumContentsRenamePlan.resolve(album: '', newName: 'Trips');

    expect(plan.isValid, isFalse);
    expect(plan.error, AlbumContentsRenameError.noAlbum);
  });
}
