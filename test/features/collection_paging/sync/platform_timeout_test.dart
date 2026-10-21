import 'dart:async';

import 'package:aves/features/collection_paging/sync/platform_timeout.dart';
import 'package:flutter_test/flutter_test.dart';

/// A platform step that never answers must not be able to freeze a resolve: it
/// is bounded and reported as missing, and the database still answers the view.
void main() {
  const short = Duration(milliseconds: 20);

  test('a step that answers passes its value through', () async {
    final value = await withPlatformTimeout(() async => 42, label: 'generation', timeout: short);
    expect(value, 42);
  });

  test('a step that never answers is bounded and reads as missing', () async {
    final never = Completer<int>();
    addTearDown(() => never.complete(0));
    final value = await withPlatformTimeout(() => never.future, label: 'generation', timeout: short);
    expect(value, isNull);
  });

  test('a failing step is reported, not thrown at the resolve', () async {
    final value = await withPlatformTimeout<int>(() async => throw StateError('no store'), label: 'generation', timeout: short);
    expect(value, isNull);
  });
}
