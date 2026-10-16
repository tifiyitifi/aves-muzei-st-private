import 'package:aves/features/collection_paging/query/shuffle_permutation.dart';
import 'package:flutter_test/flutter_test.dart';

/// The seeded permutation must be a true bijection for every size and seed:
/// no collisions, no dropped items, exact inverse, deterministic per seed.
void main() {
  // Sizes covering every Feistel regime: powers of two, powers of four, odd-t
  // bands and even-t-but-not-power-of-4 bands, plus larger counts.
  const sizes = [1, 2, 3, 4, 5, 8, 9, 15, 16, 17, 31, 32, 33, 64, 100, 1000];
  const seeds = [1, 42, 12345, 987654321];

  group('ShufflePermutation', () {
    for (final n in sizes) {
      test('N=$n forward is a permutation of [0,N) and inverse is its mirror', () {
        for (final seed in seeds) {
          final permutation = ShufflePermutation(seed, n);
          final forward = [for (var i = 0; i < n; i++) permutation.forward(i)];

          // Full permutation: every real index exactly once, none dropped.
          expect(forward.toSet(), {for (var i = 0; i < n; i++) i}, reason: 'seed=$seed forward=$forward');

          // inverse is the exact inverse on both sides.
          for (var i = 0; i < n; i++) {
            expect(permutation.inverse(permutation.forward(i)), i, reason: 'seed=$seed i=$i');
            expect(permutation.forward(permutation.inverse(i)), i, reason: 'seed=$seed i=$i');
          }
        }
      });
    }

    test('deterministic for the same seed', () {
      const n = 33;
      final a = ShufflePermutation(20260806, n);
      final b = ShufflePermutation(20260806, n);
      expect([for (var i = 0; i < n; i++) a.forward(i)], [for (var i = 0; i < n; i++) b.forward(i)]);
    });

    test('different seeds generally differ', () {
      const n = 100;
      final a = [for (var i = 0; i < n; i++) ShufflePermutation(1, n).forward(i)];
      final b = [for (var i = 0; i < n; i++) ShufflePermutation(2, n).forward(i)];
      expect(a, isNot(equals(b)));
    });

    test('handles an empty collection', () {
      final permutation = ShufflePermutation(7, 0);
      expect(permutation.forward(0), 0);
      expect(permutation.inverse(0), 0);
    });
  });
}
