import 'package:aves/features/refra_edit/model/refra_edit_paths.dart';
import 'package:flutter_test/flutter_test.dart';

/// File identity inside the staging tree.
///
/// The media operation and the scanner name the primary volume differently, so the same file must
/// reduce to one key or an edit records its own copy twice and the move back submits it twice.
void main() {
  test('the same media row keeps one key across volume aliases', () {
    final keys = {
      refraEditFileKey(path: '', uri: 'content://media/external_primary/images/media/42', fileName: 'a.jpg', sizeBytes: 10),
      refraEditFileKey(path: '', uri: 'content://media/external/images/media/42', fileName: 'a.jpg', sizeBytes: 10),
      refraEditFileKey(path: '', uri: 'content://media/external/file/42', fileName: 'a.jpg', sizeBytes: 10),
    };
    expect(keys, hasLength(1));
    expect(keys.single, 'media:42');
  });

  test('different media rows stay apart', () {
    expect(
      refraEditFileKey(path: '', uri: 'content://media/external/images/media/1', fileName: 'a.jpg', sizeBytes: 10),
      isNot(refraEditFileKey(path: '', uri: 'content://media/external/images/media/2', fileName: 'a.jpg', sizeBytes: 10)),
    );
  });

  test('a file uri falls back to its path', () {
    expect(
      refraEditFileKey(path: '/storage/emulated/0/Pictures/aves_refra_edit/a.jpg', uri: 'file:///storage/emulated/0/Pictures/aves_refra_edit/a.jpg', fileName: 'a.jpg', sizeBytes: 10),
      'path:/storage/emulated/0/pictures/aves_refra_edit/a.jpg',
    );
  });

  test('without a uri or path the name and size identify the file', () {
    expect(
      refraEditFileKey(path: '', uri: '', fileName: 'A.jpg', sizeBytes: 10),
      refraEditFileKey(path: '', uri: '', fileName: 'a.jpg', sizeBytes: 10),
    );
    expect(
      refraEditFileKey(path: '', uri: '', fileName: 'a.jpg', sizeBytes: 10),
      isNot(refraEditFileKey(path: '', uri: '', fileName: 'a.jpg', sizeBytes: 11)),
    );
  });
}
