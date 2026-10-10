/// spec rule `number.round2`: round to 2 decimal places, half away from zero,
/// on the shortest round-trip decimal of [x] (what `x.toString()` prints), not
/// on its binary value. Never returns `-0.0`. [x] must be finite.
double round2(double x) {
  // Every double of magnitude 2^53 or more is an integer, so this also covers
  // the values toString() prints with a positive exponent.
  if (x == x.truncateToDouble()) return x == 0 ? 0.0 : x;

  final s = x.abs().toString();
  // A non-integer in exponent notation is below 1e-6 in magnitude.
  if (s.contains('e')) return 0.0;

  final dot = s.indexOf('.');
  final frac = s.substring(dot + 1);
  if (frac.length <= 2) return x;

  // Exact decimal arithmetic on the digits, never on the binary value.
  var hundredths = BigInt.parse(s.substring(0, dot) + frac.substring(0, 2));
  if (frac.codeUnitAt(2) >= 0x35 /* '5' */ ) hundredths += BigInt.one;
  final hundred = BigInt.from(100);
  final magnitude = double.parse(
    '${hundredths ~/ hundred}.${(hundredths % hundred).toString().padLeft(2, '0')}',
  );
  return x < 0 && magnitude != 0 ? -magnitude : magnitude;
}
