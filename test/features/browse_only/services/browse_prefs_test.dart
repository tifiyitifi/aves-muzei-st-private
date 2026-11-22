import 'package:aves/features/browse_only/services/browse_prefs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../common.dart';

/// The browser's sort preferences: its own namespace, gallery defaults, and a
/// read that cannot block the surface.
void main() {
  setUpAll(() async {
    await setUpAllServices();
  });

  tearDownAll(() async {
    await tearDownAllServices();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('starts from the gallery defaults', () async {
    final prefs = BrowsePrefs();

    await prefs.init();

    expect(prefs.mediaSort, BrowseMediaSort.date);
    expect(prefs.mediaReverse, isFalse);
    expect(prefs.albumSort, BrowseAlbumSort.date);
    expect(prefs.albumReverse, isFalse);
    expect(prefs.isLoaded, isTrue);
  });

  test('reads the persisted sort and direction', () async {
    SharedPreferences.setMockInitialValues({
      'browse_only.media_sort': 'name',
      'browse_only.media_reverse': true,
      'browse_only.album_sort': 'count',
      'browse_only.album_reverse': true,
    });

    final prefs = BrowsePrefs();
    await prefs.init();

    expect(prefs.mediaSort, BrowseMediaSort.name);
    expect(prefs.mediaReverse, isTrue);
    expect(prefs.albumSort, BrowseAlbumSort.count);
    expect(prefs.albumReverse, isTrue);
  });

  test('keeps the default for a value it cannot read', () async {
    SharedPreferences.setMockInitialValues({'browse_only.media_sort': 'ghost'});

    final prefs = BrowsePrefs();
    await prefs.init();

    // A corrupt enum name is not a reason to lose the direction or the album
    // defaults.
    expect(prefs.mediaSort, BrowseMediaSort.date);
    expect(prefs.albumSort, BrowseAlbumSort.date);
  });

  test('persists a picked media sort under its own keys', () async {
    final prefs = BrowsePrefs();
    await prefs.init();

    prefs.setMediaSort(BrowseMediaSort.name, true);
    await pumpEventQueue();

    final store = await SharedPreferences.getInstance();
    expect(store.getString('browse_only.media_sort'), 'name');
    expect(store.getBool('browse_only.media_reverse'), isTrue);
    // The collection's own sort keys are untouched.
    expect(store.getString('collection_sort'), isNull);
  });

  test('persists a picked album sort under its own keys', () async {
    final prefs = BrowsePrefs();
    await prefs.init();

    prefs.setAlbumSort(BrowseAlbumSort.count, false);
    await pumpEventQueue();

    final store = await SharedPreferences.getInstance();
    expect(store.getString('browse_only.album_sort'), 'count');
    expect(store.getBool('browse_only.album_reverse'), isFalse);
  });

  test('picking the current sort neither notifies nor writes', () async {
    final prefs = BrowsePrefs();
    await prefs.init();
    var notifications = 0;
    prefs.addListener(() => notifications++);

    prefs.setMediaSort(prefs.mediaSort, prefs.mediaReverse);
    prefs.setAlbumSort(prefs.albumSort, prefs.albumReverse);
    await pumpEventQueue();

    expect(notifications, 0);
    final store = await SharedPreferences.getInstance();
    expect(store.getString('browse_only.media_sort'), isNull);
    expect(store.getString('browse_only.album_sort'), isNull);
  });

  test('init reads once and later calls do not re-read', () async {
    final prefs = BrowsePrefs();
    await prefs.init();

    SharedPreferences.setMockInitialValues({'browse_only.media_sort': 'name'});
    await prefs.init();

    expect(prefs.mediaSort, BrowseMediaSort.date);
  });
}
