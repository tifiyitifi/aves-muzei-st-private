import 'package:aves/features/muzei_wallpaper/model/wallpaper_share_uri.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:flutter_test/flutter_test.dart';

AvesEntry _entry({String? path}) => AvesEntry(
  id: 42,
  uri: 'content://media/external/images/media/42',
  path: path,
  contentId: 142,
  pageId: null,
  sourceMimeType: 'image/jpeg',
  width: 10,
  height: 20,
  sourceRotationDegrees: 0,
  sizeBytes: 5,
  sourceTitle: 'title',
  dateAddedSecs: 1,
  dateModifiedMillis: 2,
  sourceDateTakenMillis: 3,
  durationMillis: 0,
  trashed: false,
  origin: EntryOrigins.mediaStoreContent,
);

void main() {
  test('prefers a file URI so the receiver reads the bytes directly', () {
    const path = '/storage/emulated/0/Pictures/a b.jpg';
    final uri = wallpaperShareUri(_entry(path: path));

    // The native side turns this into the app's read-only FileProvider URI.
    expect(uri, Uri.file(path).toString());
    expect(uri, startsWith('file://'));
  });

  test('keeps the MediaStore URI when no path is known', () {
    expect(wallpaperShareUri(_entry(path: null)), 'content://media/external/images/media/42');
    expect(wallpaperShareUri(_entry(path: '')), 'content://media/external/images/media/42');
  });
}
