import 'package:aves/features/search_filters/model/search_assist.dart';

/// Units the assist offers for a size bound.
enum AssistSizeUnit {
  kb(1 << 10),
  mb(1 << 20),
  gb(1 << 30);

  final int bytes;

  new(this.bytes);
}

/// Bytes for a size field, or null when the text is blank, unparsable or not
/// positive: an empty field means "no bound", not "zero bytes".
int? sizeBytesOf(String text, AssistSizeUnit unit) {
  final value = double.tryParse(text.trim());
  if (value == null || value <= 0) return null;
  return (value * unit.bytes).round();
}

/// Converts a displayed bound between units; the byte value is the invariant.
double? convertSizeValue(double? value, {required AssistSizeUnit from, required AssistSizeUnit to}) {
  return value == null ? null : value * from.bytes / to.bytes;
}

/// Formats a displayed bound, keeping two decimals for ordinary sizes.
///
/// Rounding a positive value to `0` would read back as "no bound" and silently
/// widen the filter, so such a value keeps significant digits instead.
String formatSizeValue(double? value) {
  if (value == null) return '';
  final rounded = (value * 100).round() / 100;
  if (rounded == 0 && value != 0) return _significantDigits(value);
  return rounded == rounded.roundToDouble() ? '${rounded.round()}' : '$rounded';
}

/// The largest unit that represents the picked bound exactly, so reopening the
/// sheet never rounds a size the user already set.
///
/// The lower bound decides, the upper one stands in when it is absent.
AssistSizeUnit bestSizeUnit(AssistIntRange? range) {
  final bytes = range?.min ?? range?.max;
  if (bytes == null) return AssistSizeUnit.mb;
  for (final unit in [AssistSizeUnit.gb, AssistSizeUnit.mb, AssistSizeUnit.kb]) {
    if (bytes % unit.bytes == 0) return unit;
  }
  return AssistSizeUnit.kb;
}

String _significantDigits(double value) {
  final text = value.toStringAsPrecision(4);
  if (text.contains('e')) return text;
  return text.contains('.') ? text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '') : text;
}
