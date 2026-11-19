import 'package:aves/model/entry/entry.dart';
import 'package:aves/widgets/viewer/hero.dart';
import 'package:flutter_test/flutter_test.dart';

/// The hero tag identifies *the row*, not the file's URI.
///
/// Two rows can carry the same media URI — a duplicate the database now rejects
/// (see `MigrationV16`), but an older database may still hold one. Sharing a tag
/// makes Flutter abort the transition with "multiple heroes share the same tag",
/// which is exactly what a collection → albums push used to hit.
void main() {
  AvesEntry entry({required int id, required String uri}) => AvesEntry(
        id: id,
        uri: uri,
        path: '/album/$id.jpg',
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
        origin: 0,
      );

  const sharedUri = 'content://media/external/images/media/501';

  test('two rows sharing a URI do not share a tag', () {
    final first = entry(id: 1, uri: sharedUri);
    final repeat = entry(id: 2, uri: sharedUri);

    expect(EntryHeroInfo(null, first).tag, isNot(EntryHeroInfo(null, repeat).tag));
  });

  test('the same row keeps its tag across views', () {
    final row = entry(id: 1, uri: sharedUri);

    expect(EntryHeroInfo(null, row).tag, EntryHeroInfo(null, entry(id: 1, uri: sharedUri)).tag);
  });
}
