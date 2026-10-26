import 'package:aves/features/search_filters/model/time_to_now.dart';
import 'package:flutter_test/flutter_test.dart';

/// The `TIME2NOW` token: the persisted form of a relative window.
void main() {
  test('parses hour and day tokens', () {
    expect(TimeToNow.parse('3h'), const TimeToNow(amount: 3, unit: RelativeTimeUnit.hour));
    expect(TimeToNow.parse('7D'), const TimeToNow(amount: 7, unit: RelativeTimeUnit.day));
    expect(TimeToNow.parse(' 12 h '), const TimeToNow(amount: 12, unit: RelativeTimeUnit.hour));
    expect(TimeToNow.parse('30d'), const TimeToNow(amount: 30, unit: RelativeTimeUnit.day));
  });

  test('rejects malformed and zero-width tokens', () {
    for (final token in [null, '', 'd', '3', '0d', '-3h', '3w', 'h3', '1.5d']) {
      expect(TimeToNow.parse(token), isNull, reason: '$token');
    }
  });

  test('round-trips through its token', () {
    for (final span in [
      const TimeToNow(amount: 1, unit: RelativeTimeUnit.hour),
      const TimeToNow(amount: 12, unit: RelativeTimeUnit.hour),
      const TimeToNow(amount: 30, unit: RelativeTimeUnit.day),
    ]) {
      expect(TimeToNow.parse(span.token), span, reason: span.token);
    }
  });

  test('resolves its window in milliseconds', () {
    expect(const TimeToNow(amount: 3, unit: RelativeTimeUnit.hour).millis, const Duration(hours: 3).inMilliseconds);
    expect(const TimeToNow(amount: 7, unit: RelativeTimeUnit.day).millis, const Duration(days: 7).inMilliseconds);
  });
}
