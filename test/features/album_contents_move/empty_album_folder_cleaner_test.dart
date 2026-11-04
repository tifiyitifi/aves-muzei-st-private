import 'dart:io';

import 'package:aves/features/album_contents_move/services/empty_album_folder_cleaner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('aves_empty_album_');
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  String path(String name) => p.join(root.path, name);

  Future<void> touch(String filePath) async {
    final file = File(filePath);
    await file.parent.create(recursive: true);
    await file.writeAsString('x');
  }

  test('only removes directories that are completely empty', () async {
    final empty = path('empty');
    final withFile = path('with_file');
    final withHiddenFile = path('with_hidden_file');
    final withEmptySubfolder = path('with_empty_subfolder');
    final parent = path('parent');
    final child = p.join(parent, 'child');

    await Directory(empty).create();
    await touch(p.join(withFile, 'note.txt'));
    await touch(p.join(withHiddenFile, '.nomedia'));
    await Directory(p.join(withEmptySubfolder, 'subfolder')).create(recursive: true);
    await Directory(child).create(recursive: true);

    Set<String>? deleted;
    final cleaner = EmptyAlbumFolderCleaner(
      deleteEmptyDirectories: (paths) async {
        deleted = paths;
        return paths.length;
      },
    );

    final count = await cleaner.clean([empty, withFile, withHiddenFile, withEmptySubfolder, parent, child]);

    // The pre-scan runs before any delete, so the parent still sees its child
    // and is kept. Deleting the child later cannot cascade into the parent.
    expect(deleted, {empty, child});
    expect(count, 2);
  });

  test('treats a missing or unreadable directory as non-empty', () async {
    var deleted = false;
    final cleaner = EmptyAlbumFolderCleaner(
      isEmptyCheck: (path) async => throw const FileSystemException('denied'),
      deleteEmptyDirectories: (paths) async {
        deleted = true;
        return paths.length;
      },
    );

    final count = await cleaner.clean([path('missing')]);

    expect(count, 0);
    expect(deleted, isFalse);
  });
}
