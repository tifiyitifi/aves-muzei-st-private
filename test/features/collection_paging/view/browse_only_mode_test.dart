import 'package:aves/features/collection_paging/lens/paged_import_status.dart';
import 'package:aves/features/collection_paging/view/browse_only_notice_bar.dart';
import 'package:aves_model/aves_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(pagedImportStatus.reset);

  test('locks writes, bulk actions and aggregates while the import runs', () {
    expect(BrowseOnlyMode.isActive, isFalse);
    expect(BrowseOnlyMode.locks(EntrySetAction.delete), isFalse);

    pagedImportStatus.begin(total: 10);

    for (final action in [
      EntrySetAction.select,
      EntrySetAction.selectAll,
      EntrySetAction.selectByTrait,
      EntrySetAction.share,
      EntrySetAction.copyToClipboard,
      EntrySetAction.delete,
      EntrySetAction.move,
      EntrySetAction.editRating,
      EntrySetAction.editTags,
      EntrySetAction.toggleFavourite,
      EntrySetAction.stats,
      EntrySetAction.map,
    ]) {
      expect(BrowseOnlyMode.locks(action), isTrue, reason: '$action should be locked');
    }
    for (final action in [
      EntrySetAction.changeLayout,
      EntrySetAction.searchCollection,
      EntrySetAction.slideshow,
      EntrySetAction.toggleLayoutBar,
    ]) {
      expect(BrowseOnlyMode.locks(action), isFalse, reason: '$action should stay available');
    }
  });

  test('unlocks as soon as the import ends', () {
    pagedImportStatus.begin(total: 10);
    expect(BrowseOnlyMode.locks(EntrySetAction.delete), isTrue);

    pagedImportStatus.end();
    expect(BrowseOnlyMode.isActive, isFalse);
    expect(BrowseOnlyMode.locks(EntrySetAction.delete), isFalse);
  });
}
