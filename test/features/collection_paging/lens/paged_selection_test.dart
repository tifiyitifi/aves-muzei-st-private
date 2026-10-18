import 'package:aves/features/collection_paging/lens/paged_lists.dart';
import 'package:aves/features/collection_paging/lens/skeleton_entry.dart';
import 'package:aves/features/collection_paging/windows/window_cache.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:aves/model/selection.dart';
import 'package:aves/model/source/section_keys.dart';
import 'package:flutter_test/flutter_test.dart';

/// Selection over a windowed collection: every query reads the loaded rows, so
/// "select all" never walks the lazy list — a walk would kick a window per
/// position and pick up placeholders.
void main() {
  AvesEntry entry(int id) => AvesEntry(
        id: id,
        uri: 'content://$id',
        path: '/album/$id.jpg',
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

  Selection<AvesEntry> selection() => Selection<AvesEntry>(toSelectableItems: (entry) => entry.toSelectableItems());

  /// A section whose first row is loaded and whose remaining rows are not.
  PagedSectionList section(String directory, {required int count, int? loadedId}) {
    final key = EntryAlbumSectionKey(directory);
    final list = PagedSectionList(sectionKey: key, count: count, skeleton: SkeletonEntry.forAlbum(directory, key));
    if (loadedId != null) list.loaded[0] = entry(loadedId);
    return list;
  }

  test('select all reads the loaded rows instead of walking the list', () async {
    var fetches = 0;
    // A section far larger than what is loaded: walking it would ask the cache
    // for a window at every position.
    final list = section('/a', count: 1000000, loadedId: 7);
    list.cache = WindowCache<AvesEntry>(
      windowSize: 10,
      fetch: (windowIndex, limit, offset) async {
        fetches++;
        return <AvesEntry>[];
      },
    );

    final selection0 = selection()..addToSelection(list);
    await Future<void>.delayed(Duration.zero);

    expect(fetches, 0);
    expect(selection0.selectedItems.map((entry) => entry.id), [7]);
  });

  test('a whole-collection select all narrows to the loaded sections', () {
    final flat = PagedFlatList([
      section('/a', count: 100, loadedId: 1),
      section('/b', count: 100, loadedId: 2),
    ]);

    final selection0 = selection()..addToSelection(flat);

    expect(selection0.selectedItemCount, 2);
    expect(selection0.selectedItems.map((entry) => entry.id), [1, 2]);
    // A placeholder can never reach the selection.
    expect(selection0.selectedItems.whereType<SkeletonEntry>(), isEmpty);
  });

  test('is-selected answers from the loaded rows', () {
    final flat = PagedFlatList([section('/a', count: 100, loadedId: 1)]);
    final selection0 = selection();

    expect(selection0.isSelected(flat), isFalse);
    selection0.addToSelection(flat);
    expect(selection0.isSelected(flat), isTrue);
  });

  test('a plain list is still selected whole', () {
    final selection0 = selection()..addToSelection([entry(1), entry(2)]);
    expect(selection0.selectedItemCount, 2);
  });

  test('a selection keys entries by id, not by instance', () {
    // One row served by two database reads is two instances: the tile the grid
    // shows and the entry an action collected must count as one selection.
    final selection0 = Selection<AvesEntry>(toSelectableItems: (entry) => entry.toSelectableItems(), keyOf: (entry) => entry.id);

    selection0.addToSelection({entry(1)});
    expect(selection0.isSelected({entry(1)}), isTrue);
    expect(selection0.selectedItemCount, 1);

    // The same id again does not double the count, and removal is by id too.
    selection0.addToSelection({entry(1)});
    expect(selection0.selectedItemCount, 1);
    selection0.removeFromSelection({entry(1)});
    expect(selection0.selectedItemCount, 0);
  });
}
