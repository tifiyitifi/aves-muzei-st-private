import 'package:aves/features/search_filters/model/search_assist.dart';
import 'package:aves/features/search_filters/model/size_assist_unit.dart';
import 'package:flutter_test/flutter_test.dart';

/// The size tab's arithmetic: a unit change moves the displayed numbers while
/// the byte value stays put, and no bound is ever lost to rounding.
void main() {
  test('converting a unit keeps the byte value', () {
    final inKb = convertSizeValue(2, from: AssistSizeUnit.mb, to: AssistSizeUnit.kb)!;

    expect(inKb, 2048);
    expect(sizeBytesOf('2048', AssistSizeUnit.kb), 2 << 20);
    expect(sizeBytesOf('2', AssistSizeUnit.mb), 2 << 20);
  });

  test('a round trip through two units returns to the same bound', () {
    const value = 1.5;
    final inKb = convertSizeValue(value, from: AssistSizeUnit.mb, to: AssistSizeUnit.kb)!;
    final text = formatSizeValue(inKb);
    final back = convertSizeValue(double.parse(text), from: AssistSizeUnit.kb, to: AssistSizeUnit.mb)!;

    expect(back, value);
    expect(sizeBytesOf(text, AssistSizeUnit.kb), sizeBytesOf('1.5', AssistSizeUnit.mb));
  });

  test('the largest exact unit is chosen for a stored bound', () {
    expect(bestSizeUnit(const AssistIntRange(min: 2 << 30)), AssistSizeUnit.gb);
    expect(bestSizeUnit(const AssistIntRange(min: 5 << 20)), AssistSizeUnit.mb);
    expect(bestSizeUnit(const AssistIntRange(min: 3 << 10)), AssistSizeUnit.kb);
    // Divides no unit exactly: the smallest one still represents it as a decimal.
    expect(bestSizeUnit(const AssistIntRange(min: 1500)), AssistSizeUnit.kb);
    // The upper bound stands in when the range has no lower one.
    expect(bestSizeUnit(const AssistIntRange(max: 5 << 20)), AssistSizeUnit.mb);
    expect(bestSizeUnit(null), AssistSizeUnit.mb);
  });

  test('a tiny non-zero bound does not become no bound', () {
    // Two decimals would round a sub-kilobyte bound to `0`, which reads back as
    // "no lower bound" and silently widens the filter.
    final inKb = formatSizeValue(1 / AssistSizeUnit.kb.bytes);
    expect(sizeBytesOf(inKb, AssistSizeUnit.kb), 1);

    final inGb = formatSizeValue(1 / AssistSizeUnit.gb.bytes);
    expect(sizeBytesOf(inGb, AssistSizeUnit.gb), 1);
  });

  test('an empty or negative field is no bound', () {
    expect(sizeBytesOf('', AssistSizeUnit.mb), isNull);
    expect(sizeBytesOf('   ', AssistSizeUnit.mb), isNull);
    expect(sizeBytesOf('abc', AssistSizeUnit.mb), isNull);
    expect(sizeBytesOf('0', AssistSizeUnit.mb), isNull);
    expect(sizeBytesOf('-1', AssistSizeUnit.mb), isNull);
    expect(formatSizeValue(null), '');
  });
}
