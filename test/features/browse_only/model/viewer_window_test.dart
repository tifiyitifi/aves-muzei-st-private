import 'package:aves/features/browse_only/model/viewer_window.dart';
import 'package:flutter_test/flutter_test.dart';

/// The viewer receives a bounded window around the tapped row, never the whole
/// displayed order.
void main() {
  test('a position outside the list has no window', () {
    expect(viewerWindow(length: 10, position: -1), isNull);
    expect(viewerWindow(length: 10, position: 10), isNull);
    expect(viewerWindow(length: 0, position: 0), isNull);
  });

  test('the window is bounded on both sides', () {
    final window = viewerWindow(length: 2000, position: 1000)!;

    expect(window.from, 750);
    expect(window.to, 1251);
    expect(window.to - window.from, 501);
    expect(window.from <= 1000 && 1000 < window.to, isTrue);
  });

  test('a position near the start keeps the beginning', () {
    final window = viewerWindow(length: 1000, position: 3)!;

    expect(window.from, 0);
    expect(window.to, 254);
    expect(window.to - window.from, 254);
    expect(window.from <= 3 && 3 < window.to, isTrue);
  });

  test('a position near the end keeps the end', () {
    final window = viewerWindow(length: 1000, position: 997)!;

    expect(window.from, 747);
    expect(window.to, 1000);
    expect(window.to - window.from, 253);
    expect(window.from <= 997 && 997 < window.to, isTrue);
  });
}
