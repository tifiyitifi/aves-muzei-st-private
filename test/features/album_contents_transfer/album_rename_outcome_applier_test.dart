import 'package:aves/features/album_contents_transfer/services/album_rename_outcome_applier.dart';
import 'package:aves/model/db/db.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:flutter_test/flutter_test.dart';

/// A native rename has already moved the files: the database rows and the album
/// state have to follow, in that order, so nothing reads a half-applied rename.
void main() {
  const album = '/storage/emulated/0/Pictures/Holidays';
  const destination = '/storage/emulated/0/Pictures/Trips';

  test('rewrites the rows, then moves the album state, then reloads the counts', () async {
    final events = <String>[];
    final database = _FakeDb(onRename: (oldDirectory, newDirectory) async {
      events.add('rows $oldDirectory -> $newDirectory');
    });
    final source = _FakeSource(onApply: (sourceAlbum, destinationAlbum) async {
      events.add('state $sourceAlbum -> $destinationAlbum');
    });

    final rowsMoved = await applyInstantAlbumRename(
      source: source,
      album: album,
      destination: destination,
      database: database,
      reloadSummaries: () async => events.add('reload'),
    );

    expect(rowsMoved, isTrue);
    expect(events, [
      'rows $album -> $destination',
      'state $album -> $destination',
      'reload',
    ]);
  });

  test('a failed row rewrite still carries the album state over', () async {
    final events = <String>[];
    final database = _FakeDb(onRename: (_, _) async => throw StateError('database busy'));
    final source = _FakeSource(onApply: (sourceAlbum, destinationAlbum) async {
      events.add('state $sourceAlbum -> $destinationAlbum');
    });

    final rowsMoved = await applyInstantAlbumRename(
      source: source,
      album: album,
      destination: destination,
      database: database,
      reloadSummaries: () async => events.add('reload'),
    );

    // The files moved, so the album must not point at a folder whose rows never
    // arrived: the state follows, and a later scan re-reads the paths.
    expect(rowsMoved, isFalse);
    expect(events, [
      'state $album -> $destination',
      'reload',
    ]);
  });
}

class _FakeDb extends Fake implements LocalMediaDb {
  final Future<void> Function(String oldDirectory, String newDirectory)? onRename;

  new({this.onRename});

  @override
  Future<int> renameDirectoryPrefix({required String oldDirectory, required String newDirectory}) async {
    await onRename?.call(oldDirectory, newDirectory);
    return 1;
  }
}

class _FakeSource extends Fake implements CollectionSource {
  final Future<void> Function(String sourceAlbum, String destinationAlbum)? onApply;

  new({this.onApply});

  @override
  Future<void> applyStoredAlbumRename(String sourceAlbum, String destinationAlbum, {Future<void> Function()? move}) async {
    await onApply?.call(sourceAlbum, destinationAlbum);
  }
}
