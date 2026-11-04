import 'dart:io';

import 'package:aves/services/common/services.dart';

typedef EmptyDirectoryCheck = Future<bool> Function(String path);
typedef EmptyDirectoryDelete = Future<int> Function(Set<String> paths);

/// Whether [path] is a directory with no entries at all.
///
/// `list()` includes hidden files and subdirectories, so a `.nomedia`, a
/// thumbnail, or even an empty subfolder makes the directory non-empty.
Future<bool> isDirectoryEmpty(String path) async {
  final directory = Directory(path);
  if (!await directory.exists()) return false;
  return directory.list(followLinks: false).isEmpty;
}

/// Removes album folders only after proving they are empty.
///
/// The pre-scan finishes before the first deletion. Deleting an empty child
/// therefore cannot make its parent look empty and cascade into removing it:
/// the parent still held that child when its own emptiness was checked. The
/// platform call then re-checks every directory immediately before `rmdir`, so
/// a file that appears in the meantime still blocks the delete.
class EmptyAlbumFolderCleaner {
  final EmptyDirectoryCheck? isEmptyCheck;
  final EmptyDirectoryDelete? deleteEmptyDirectories;

  const new({
    this.isEmptyCheck,
    this.deleteEmptyDirectories,
  });

  Future<int> clean(Iterable<String> candidates) async {
    final check = isEmptyCheck ?? isDirectoryEmpty;
    final delete = deleteEmptyDirectories ?? _deleteEmptyDirectories;

    final verified = <String>{};
    for (final path in candidates) {
      try {
        if (await check(path)) verified.add(path);
      } catch (_) {
        // Unreadable is not empty: keep the folder.
      }
    }
    if (verified.isEmpty) return 0;
    return delete(verified);
  }
}

Future<int> _deleteEmptyDirectories(Set<String> paths) => storageService.deleteEmptyRegularDirectories(paths);
