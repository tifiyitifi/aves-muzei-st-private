/// Seeded permutation of `[0, totalCount)` computed on the fly.
///
/// A four-round Feistel network over a power-of-four domain plus cycle-walking
/// yields a bijection for any size: [forward] maps a shuffled (virtual) position
/// to the entry's index in the collection's own order, so a shuffled slideshow
/// can be walked one position at a time (`loadEntryWindow(offset: forward(v),
/// limit: 1)`) without materializing or re-sorting the collection. [inverse] is
/// the exact reverse, which lets a re-shuffle keep the current entry in place.
///
/// Ported from iris's `FeistelShuffle`; the invariants (true permutation,
/// inverse mirror, same seed ⇒ same order) are covered by
/// `test/features/collection_paging/shuffle_permutation_test.dart`.
class ShufflePermutation {
  final int seed;
  final int totalCount;

  /// Feistel permutation half-width: the domain is 2^(2*halfBits), always
  /// >= [totalCount], so the permutation covers every real index.
  final int _halfBits;
  final int _halfMask;

  new(this.seed, this.totalCount)
      : _halfBits = _halfBitsFor(totalCount),
        _halfMask = (1 << _halfBitsFor(totalCount)) - 1;

  /// Maps a virtual (shuffled) position to the real (original) position.
  ///
  /// The Feistel function is a bijection on `[0, domainSize)`; cycle-walking
  /// rejects every result `>= totalCount`, yielding a permutation of
  /// `[0, totalCount)` for any size (no collisions, no dropped items).
  int forward(int virtualPos) {
    if (totalCount <= 1) return totalCount == 0 ? 0 : virtualPos.clamp(0, 0);
    var x = virtualPos;
    do {
      x = _feistel(x);
    } while (x >= totalCount);
    return x;
  }

  /// Maps a real (original) position back to the virtual (shuffled) position.
  int inverse(int originalPos) {
    if (totalCount <= 1) return totalCount == 0 ? 0 : originalPos.clamp(0, 0);
    var x = originalPos;
    do {
      x = _inverseFeistel(x);
    } while (x >= totalCount);
    return x;
  }

  int _feistel(int x) {
    var l = (x >> _halfBits) & _halfMask;
    var r = x & _halfMask;
    for (var round = 0; round < 4; round++) {
      final newL = r;
      final newR = l ^ _roundFunction(r, round);
      l = newL;
      r = newR;
    }
    return ((l & _halfMask) << _halfBits) | (r & _halfMask);
  }

  int _inverseFeistel(int x) {
    var l = (x >> _halfBits) & _halfMask;
    var r = x & _halfMask;
    for (var round = 3; round >= 0; round--) {
      final newR = l;
      final newL = r ^ _roundFunction(l, round);
      l = newL;
      r = newR;
    }
    return ((l & _halfMask) << _halfBits) | (r & _halfMask);
  }

  int _roundFunction(int value, int round) => _simpleHash('${seed}_${round}_$value') & _halfMask;

  static int _simpleHash(String input) {
    var hash = 5381;
    for (var i = 0; i < input.length; i++) {
      hash = ((hash << 5) + hash) + input.codeUnitAt(i);
      hash = hash & 0x7FFFFFFF;
    }
    return hash;
  }

  static int _nextPowerOf2(int n) {
    if (n <= 1) return 1;
    var power = 1;
    while (power < n) {
      power <<= 1;
    }
    return power;
  }

  static int _log2(int n) {
    var result = 0;
    while (n > 1) {
      n >>= 1;
      result++;
    }
    return result;
  }

  /// Smallest half-width whose Feistel domain (2^(2*halfBits)) covers
  /// [totalCount]. `ceil(ceilLog2(totalCount) / 2)`.
  static int _halfBitsFor(int totalCount) => (_log2(_nextPowerOf2(totalCount)) + 1) ~/ 2;
}
