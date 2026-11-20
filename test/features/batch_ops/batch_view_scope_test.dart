import 'package:aves/features/batch_ops/model/batch_view_scope.dart';
import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:flutter_test/flutter_test.dart';

/// The results banner offers to replace originals, so it must be scoped to the
/// folder's own view. A broader album, a second filter or a share folder would
/// put actions on screen for rows the user cannot see.
void main() {
  const resultsDir = '/storage/emulated/0/Pictures/aves_batch_results';
  const shareDir = '/storage/emulated/0/Pictures/aves_share';
  const cameraDir = '/storage/emulated/0/DCIM/Camera';

  test('shows the banner only in the results folder view', () {
    expect(isBatchResultsView({StoredAlbumFilter(resultsDir, null)}), isTrue);
    expect(isBatchResultsView({StoredAlbumFilter(shareDir, null)}), isFalse);
    expect(isBatchResultsView({StoredAlbumFilter(cameraDir, null)}), isFalse);
    expect(
      isBatchResultsView({StoredAlbumFilter(resultsDir, null), StoredAlbumFilter(cameraDir, null)}),
      isFalse,
      reason: 'a multi-filter view is not the folder itself',
    );
    expect(isBatchResultsView({}), isFalse);
  });
}
