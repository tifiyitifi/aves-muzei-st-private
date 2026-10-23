import 'package:aves/model/entry/entry.dart';
import 'package:aves/services/media/media_fetch_service.dart';
import 'package:collection/collection.dart';
import 'package:test/fake.dart';

class FakeMediaFetchService extends Fake implements MediaFetchService {
  Set<AvesEntry> entries = {};

  /// URIs whose read fails, for a test that must prove a transient failure is
  /// retried instead of being lost with the generation cursor.
  Set<String> failingUris = {};

  /// Decoder caches live on the platform; nothing to clear here. Called when a
  /// catalogued mime/rotation replaces the source one on an entry.
  @override
  Future<void> clearDecoders() async {}

  @override
  Future<AvesEntry?> getEntry(String uri, String? mimeType, {bool allowUnsized = false}) async {
    if (failingUris.contains(uri)) throw StateError('fetch failed for $uri');
    return entries.firstWhereOrNull((v) => v.uri == uri);
  }
}
