import 'dart:math';

/// A small seeded generator (mulberry32), the same one the website and API
/// use (`seededRandom` in packages/shared/src/drafts.ts), so a seed deals
/// the same teams on every platform. Dart's own `Random(seed)` gives a
/// different sequence (and a different one again when compiled to
/// JavaScript).
///
/// The arithmetic stays within 32 bits, so it gives the same numbers on
/// the VM and on the web.
class SeededRandom implements Random {
  SeededRandom(int seed) : _state = seed & _mask;

  static const _mask = 0xffffffff;
  int _state;

  /// The next number in [0, 1), as mulberry32 gives it.
  @override
  double nextDouble() {
    _state = (_state + 0x6d2b79f5) & _mask;
    var t = _state;
    t = _imul(t ^ (t >> 15), t | 1);
    t = (t ^ ((t + _imul(t ^ (t >> 7), t | 61)) & _mask)) & _mask;
    return ((t ^ (t >> 14)) & _mask) / 4294967296;
  }

  /// A whole number in [0, max), as `Math.floor(random() * max)`.
  @override
  int nextInt(int max) {
    if (max <= 0) throw RangeError.range(max, 1, null, 'max');
    return (nextDouble() * max).floor();
  }

  @override
  bool nextBool() => nextDouble() < 0.5;

  /// 32-bit multiplication (JavaScript's `Math.imul`), split into 16-bit
  /// halves so no product loses precision on the web.
  static int _imul(int a, int b) {
    final ah = (a >> 16) & 0xffff, al = a & 0xffff;
    final bh = (b >> 16) & 0xffff, bl = b & 0xffff;
    return (al * bl + ((((ah * bl + al * bh) & 0xffff) << 16) & _mask)) & _mask;
  }
}

/// Shuffles [list] in place the way packages/shared's `shuffle` does
/// (Fisher-Yates from the end).
void shuffleWith<T>(List<T> list, Random random) {
  for (var i = list.length - 1; i > 0; i--) {
    final j = random.nextInt(i + 1);
    final tmp = list[i];
    list[i] = list[j];
    list[j] = tmp;
  }
}
