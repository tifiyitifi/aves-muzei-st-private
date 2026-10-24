import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:aves/features/muzei_wallpaper/view/slot_artwork_image.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// `SlotArtworkImage`: the preview's cache identity follows the artwork, not
/// the slot path that the controller overwrites for every bake.
void main() {
  final slotPath = p.join('slots', '0', 'sharp.png');

  test('the same slot path with another artwork is a different cache entry', () {
    final first = SlotArtworkImageKey(path: slotPath, contentKey: 11, scale: 1);
    final second = SlotArtworkImageKey(path: slotPath, contentKey: 12, scale: 1);

    // A path-keyed image would treat these as the same entry and keep painting
    // the decode of the first artwork.
    expect(first, isNot(second));
    expect(first.hashCode, isNot(second.hashCode));
  });

  test('the same artwork in the same slot keeps its cache entry', () {
    final first = SlotArtworkImageKey(path: slotPath, contentKey: 11, scale: 1);
    final repeat = SlotArtworkImageKey(path: slotPath, contentKey: 11, scale: 1);

    expect(first, repeat);
    expect(first.hashCode, repeat.hashCode);
  });

  test('the slot path alone does not identify the entry', () {
    final first = SlotArtworkImageKey(path: slotPath, contentKey: 11, scale: 1);
    final otherSlot = SlotArtworkImageKey(path: p.join('slots', '1', 'sharp.png'), contentKey: 11, scale: 1);

    expect(first, isNot(otherSlot));
  });

  test('obtainKey carries the file path and the artwork identity', () async {
    final file = File(slotPath);
    final key = await SlotArtworkImage(file: file, contentKey: 42).obtainKey(ImageConfiguration.empty);

    expect(key.path, slotPath);
    expect(key.contentKey, 42);
    expect(key.scale, 1.0);
  });

  testWidgets('the preview repaints when the same slot path holds a new artwork', (tester) async {
    final tempDir = await tester.runAsync(() => Directory.systemTemp.createTemp('aves_muzei_image_'));
    addTearDown(() => tempDir!.delete(recursive: true));
    final file = File(p.join(tempDir!.path, 'sharp.png'));

    await tester.runAsync(() async {
      await file.writeAsBytes(await _png(2, 2));
      await tester.pumpWidget(_host(file, contentKey: 1));
      await _pumpUntil(tester, width: 2);

      // The controller reuses the slot path for the next artwork.
      await file.writeAsBytes(await _png(4, 4));
      await tester.pumpWidget(_host(file, contentKey: 2));
      await _pumpUntil(tester, width: 4);

      expect(_decodedWidth(tester), 4);
    });
  });
}

Widget _host(File file, {required int contentKey}) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: Image(
      image: SlotArtworkImage(file: file, contentKey: contentKey),
      fit: BoxFit.cover,
    ),
  );
}

int? _decodedWidth(WidgetTester tester) => tester.widget<RawImage>(find.byType(RawImage)).image?.width;

Future<void> _pumpUntil(WidgetTester tester, {required int width}) async {
  for (var i = 0; i < 200; i++) {
    // Inside `runAsync` this yields to the real event loop, which is where the
    // file read and the image decoder complete.
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await tester.pump();
    if (_decodedWidth(tester) == width) return;
  }
  fail('the image did not decode to width $width, current=${_decodedWidth(tester)}');
}

Future<Uint8List> _png(int width, int height) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFFFF0000),
  );
  final image = await recorder.endRecording().toImage(width, height);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}
