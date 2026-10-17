import 'package:aves/features/stacking/model/stack_grouping.dart';
import 'package:aves/ref/bursts.dart';
import 'package:aves/ref/mime_types.dart';
import 'package:aves/services/common/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// The stack policy on its own: what a group's tile is, and who hides behind it.
void main() {
  setUpAll(() {
    // `pContext` (used for base names and extensions) comes from GetIt.
    getIt.registerLazySingleton<p.Context>(() => p.Context(style: p.Style.posix));
  });

  tearDownAll(getIt.reset);

  StackRow row(int id, String path, {String mime = MimeTypes.jpeg}) => (id: id, path: path, mimeType: mime);

  test('a base name is the file name without its extension', () {
    expect(StackGrouping.baseNameOf('/a/b.tar.gz'), 'b.tar');
    expect(StackGrouping.baseNameOf('/a/.jpg'), '.jpg');
    expect(StackGrouping.baseNameOf(null), null);
  });

  test('the burst key needs a directory, a base name and a matching pattern', () {
    const patterns = [BurstPatterns.samsung];
    expect(StackGrouping.stackKeyOf(directory: '/cam', baseName: '20151021_072800_007', patterns: patterns), '/cam/20151021_072800');
    expect(StackGrouping.stackKeyOf(directory: null, baseName: '20151021_072800_007', patterns: patterns), null);
    expect(StackGrouping.stackKeyOf(directory: '/cam', baseName: 'IMG_1', patterns: patterns), null);
    expect(StackGrouping.stackKeyOf(directory: '/cam', baseName: '20151021_072800_007', patterns: const []), null);
  });

  test('a burst tiles its first frame by natural name', () {
    final rows = [row(1, '/cam/IMG_10.jpg'), row(2, '/cam/IMG_2.jpg')];
    // `IMG_2` sorts before `IMG_10`, as the legacy `compareByName` does.
    expect(StackGrouping.tileIds(rows, hasBurstKey: true), {1: 2, 2: null});
  });

  test('the extension breaks a name tie', () {
    final rows = [row(1, '/cam/IMG_2.jpg'), row(2, '/cam/IMG_2.dng', mime: MimeTypes.dng)];
    // `.dng` sorts first, and it survives because the frame it would pair with
    // was already hidden by the burst pass.
    expect(StackGrouping.tileIds(rows, hasBurstKey: true), {1: 2, 2: null});
  });

  test('without a burst the developed image hides its raw sibling', () {
    final rows = [row(1, '/cam/IMG_2.dng', mime: MimeTypes.dng), row(2, '/cam/IMG_2.jpg')];
    expect(StackGrouping.tileIds(rows, hasBurstKey: false), {1: 2, 2: null});
  });

  test('keyless raws without a developed image all show', () {
    final rows = [row(1, '/cam/IMG_2.dng', mime: MimeTypes.dng), row(2, '/cam/IMG_2.arw', mime: MimeTypes.arw)];
    expect(StackGrouping.tileIds(rows, hasBurstKey: false), {1: null, 2: null});
  });
}
