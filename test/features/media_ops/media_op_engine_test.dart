import 'package:aves/features/media_ops/model/media_op_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MediaOpEngine', () {
    test('defaults to the fast pipeline', () {
      expect(MediaOpEngine.defaultEngine, MediaOpEngine.v2);
    });

    test('tryParse round-trips member names', () {
      for (final engine in MediaOpEngine.values) {
        expect(MediaOpEngine.tryParse(engine.name), engine);
      }
    });

    test('tryParse rejects unknown and null', () {
      expect(MediaOpEngine.tryParse('v3'), isNull);
      expect(MediaOpEngine.tryParse(''), isNull);
      expect(MediaOpEngine.tryParse(null), isNull);
    });

    test('declares exactly the legacy and fast pipelines', () {
      expect(MediaOpEngine.values, [MediaOpEngine.v1, MediaOpEngine.v2]);
    });
  });
}
