import 'package:aves/features/meta_settings/data/value_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MetaSettingsValueCodec', () {
    test('bool round trips', () {
      expect(MetaSettingsValueCodec.decodeBool(MetaSettingsValueCodec.encodeBool(true)), isTrue);
      expect(MetaSettingsValueCodec.decodeBool(MetaSettingsValueCodec.encodeBool(false)), isFalse);
    });

    test('int round trips', () {
      expect(MetaSettingsValueCodec.decodeInt(MetaSettingsValueCodec.encodeInt(-3)), -3);
    });

    test('double round trips', () {
      expect(MetaSettingsValueCodec.decodeDouble(MetaSettingsValueCodec.encodeDouble(1.25)), 1.25);
    });

    test('string round trips verbatim', () {
      expect(MetaSettingsValueCodec.decodeString(MetaSettingsValueCodec.encodeString('a,b')), 'a,b');
    });

    test('string list round trips through json', () {
      expect(MetaSettingsValueCodec.decodeStringList(MetaSettingsValueCodec.encodeStringList(['a', 'b'])), ['a', 'b']);
    });

    test('malformed values decode to null instead of throwing', () {
      expect(MetaSettingsValueCodec.decodeBool('x'), isNull);
      expect(MetaSettingsValueCodec.decodeInt('x'), isNull);
      expect(MetaSettingsValueCodec.decodeDouble('x'), isNull);
      expect(MetaSettingsValueCodec.decodeStringList('{'), isNull);
    });

    test('a json array with non-string elements decodes to null', () {
      // `List.cast` is lazy, so returning the view would throw on first access;
      // the decoder must reject it eagerly instead.
      expect(MetaSettingsValueCodec.decodeStringList('[1,2]'), isNull);
      expect(MetaSettingsValueCodec.decodeStringList('["a",2]'), isNull);
      // valid data still yields a real (non-lazy) list
      expect(MetaSettingsValueCodec.decodeStringList(MetaSettingsValueCodec.encodeStringList(['a']))!.runtimeType, List<String>);
    });
  });
}
