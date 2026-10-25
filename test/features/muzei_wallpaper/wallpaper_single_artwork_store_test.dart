import 'dart:io';
import 'dart:typed_data';

import 'package:aves/features/muzei_wallpaper/services/wallpaper_single_artwork_store.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:aves/ref/mime_types.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../common.dart';

void main() {
  late Directory root;
  late Uint8List bytes;
  late int? freeBytes;
  var nextId = 0;

  setUpAll(() async {
    await setUpAllServices();
  });

  tearDownAll(() async {
    await tearDownAllServices();
  });

  setUp(() async {
    nextId = 0;
    root = await Directory.systemTemp.createTemp('aves_muzei_single_');
    bytes = Uint8List.fromList(const [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);
    freeBytes = 1024 * 1024 * 1024;
  });

  tearDown(() async {
    try {
      await root.delete(recursive: true);
    } catch (_) {
      // Best-effort cleanup; the assertion result is more useful.
    }
  });

  WallpaperSingleArtworkStore store() => WallpaperSingleArtworkStore(
    root,
    fetchBytes: (_) async => bytes,
    freeSpace: (_) async => freeBytes,
  );

  AvesEntry entry({
    String mime = MimeTypes.jpeg,
    String? extension,
    int width = 400,
    int height = 300,
    int rotationDegrees = 0,
  }) {
    final id = ++nextId;
    final ext = extension ?? (mime == MimeTypes.png ? 'png' : 'jpg');
    return AvesEntry(
      id: id,
      uri: 'content://$id',
      path: '/album/$id.$ext',
      contentId: 100 + id,
      pageId: null,
      sourceMimeType: mime,
      width: width,
      height: height,
      sourceRotationDegrees: rotationDegrees,
      sizeBytes: 6,
      sourceTitle: 'photo$id',
      dateAddedSecs: 1,
      dateModifiedMillis: 2,
      sourceDateTakenMillis: 3,
      durationMillis: 0,
      trashed: false,
      origin: EntryOrigins.mediaStoreContent,
    );
  }

  Future<List<FileSystemEntity>> sourceFiles() async {
    final dir = Directory(p.join(root.path, WallpaperSingleArtworkStore.sourceDirName));
    if (!await dir.exists()) return const [];
    return dir.list().toList();
  }

  group('WallpaperSingleArtworkStore', () {
    test('copies a passthrough format verbatim and keeps its metadata', () async {
      final source = entry(rotationDegrees: 90);
      final artwork = await store().copy(source);

      expect(artwork.relativePath, 'source/single.jpg');
      expect(artwork.entryId, source.id);
      expect(artwork.mimeType, MimeTypes.jpeg);
      expect(artwork.title, source.bestTitle);
      expect(artwork.width, 400);
      expect(artwork.height, 300);
      expect(artwork.rotationDegrees, 90);
      expect(artwork.sizeBytes, bytes.length);

      final file = File(p.join(root.path, artwork.relativePath));
      expect(await file.readAsBytes(), bytes);
      expect(await sourceFiles(), hasLength(1));
    });

    test('records the real format and orientation of a re-encoded copy', () async {
      // HEIC travels through the platform, which streams JPEG with the rotation
      // already applied; replaying the original rotation would rotate it twice.
      final source = entry(mime: 'image/heic', extension: 'heic', width: 400, height: 300, rotationDegrees: 90);
      final artwork = await store().copy(source);

      expect(artwork.mimeType, MimeTypes.jpeg);
      expect(artwork.rotationDegrees, 0);
      expect(artwork.isFlipped, isFalse);
      expect(artwork.relativePath, 'source/single.jpg');
      // `width`/`height` describe the decoded file, which is in display space.
      expect(artwork.width, 300);
      expect(artwork.height, 400);
    });

    test('a re-encoded PNG copy is written with a PNG extension', () async {
      bytes = Uint8List.fromList(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00]);
      final artwork = await store().copy(entry(mime: 'image/avif', extension: 'avif'));

      expect(artwork.mimeType, MimeTypes.png);
      expect(artwork.relativePath, 'source/single.png');
    });

    test('a new copy replaces the previous one, whatever its format', () async {
      final storeUnderTest = store();
      await storeUnderTest.copy(entry());
      bytes = Uint8List.fromList(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00]);
      final artwork = await storeUnderTest.copy(entry(mime: MimeTypes.png));

      expect(artwork.relativePath, 'source/single.png');
      final files = await sourceFiles();
      expect(files, hasLength(1));
      expect(p.basename(files.single.path), 'single.png');
    });

    test('insufficient space cancels the copy and keeps the previous one', () async {
      final storeUnderTest = store();
      final first = await storeUnderTest.copy(entry());

      freeBytes = 10;
      await expectLater(
        storeUnderTest.copy(entry(mime: MimeTypes.png)),
        throwsA(isA<WallpaperSingleCopyException>().having((e) => e.isNoSpace, 'isNoSpace', isTrue)),
      );

      final files = await sourceFiles();
      expect(files, hasLength(1));
      expect(p.equals(files.single.path, File(p.join(root.path, first.relativePath)).path), isTrue);
      expect(await File(files.single.path).readAsBytes(), bytes, reason: 'the old bytes must survive');
    });

    test('an unknown free-space value does not block the copy', () async {
      freeBytes = null;
      final artwork = await store().copy(entry());
      expect(await File(p.join(root.path, artwork.relativePath)).exists(), isTrue);
    });

    test('empty bytes are rejected', () async {
      bytes = Uint8List(0);
      await expectLater(
        store().copy(entry()),
        throwsA(isA<WallpaperSingleCopyException>().having((e) => e.isNoSpace, 'isNoSpace', isFalse)),
      );
      expect(await sourceFiles(), isEmpty);
    });

    test('removeCopy deletes the source directory only', () async {
      final artwork = await store().copy(entry());
      final rootFile = File(p.join(root.path, 'state.json'));
      final slotFile = File(p.join(root.path, 'slots', '0', 'sharp.png'));
      await rootFile.writeAsString('{}');
      await slotFile.parent.create(recursive: true);
      await slotFile.writeAsBytes(const [4, 5, 6]);

      expect(await store().removeCopy(), isTrue);
      expect(await File(p.join(root.path, artwork.relativePath)).exists(), isFalse);
      expect(await sourceFiles(), isEmpty);
      expect(await rootFile.exists(), isTrue, reason: 'the state and the baked wallpaper are not the copy');
      expect(await slotFile.exists(), isTrue);
    });

    test('removeCopy is a no-op when there is no copy', () async {
      expect(await store().removeCopy(), isTrue);
    });
  });
}
