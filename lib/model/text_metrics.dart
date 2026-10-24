import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart' show rootBundle;

// Advance widths of the two bundled Pretendard files (spec/text.md "Font"),
// read from their `cmap` and `hmtx` tables. The files must be the ones in
// spec/decisions/text-font.md: any other SHA-256 is refused.

const _regularSha =
    '3ffbacde6ab8411f1d2db54bb9b1f0b3ee2a738932033722cf0388c06aed1c93';
const _boldSha =
    'c89bc43027dc7cde5726e96223376f8eec09302b2fc1f8147fd5b57cfc376118';

class FontAdvances {
  FontAdvances._(this._d, this.upm, this._nh, this._hmtx, this._cmap);

  factory FontAdvances.parse(Uint8List buf) {
    final d = ByteData.sublistView(buf);
    final tables = <String, int>{};
    for (var i = 0, n = d.getUint16(4); i < n; i++) {
      final o = 12 + i * 16;
      tables[String.fromCharCodes(buf.sublist(o, o + 4))] = d.getUint32(o + 8);
    }
    final c = tables['cmap']!;
    var off12 = -1, off4 = -1;
    for (var i = 0, n = d.getUint16(c + 2); i < n; i++) {
      final pl = d.getUint16(c + 4 + i * 8), en = d.getUint16(c + 6 + i * 8);
      final o = c + d.getUint32(c + 8 + i * 8);
      if (pl == 3 && en == 10) off12 = o;
      if (pl == 3 && en == 1) off4 = o;
    }
    if (off12 < 0 && off4 < 0) throw StateError('font has no usable cmap');
    return FontAdvances._(
      d,
      d.getUint16(tables['head']! + 18),
      d.getUint16(tables['hhea']! + 34),
      tables['hmtx']!,
      off12 >= 0 ? (true, off12) : (false, off4),
    );
  }

  final ByteData _d;
  final int upm, _nh, _hmtx;
  final (bool, int) _cmap;
  final _cache = <int, int>{};

  int _glyph(int cp) {
    final (is12, off) = _cmap;
    if (is12) {
      for (var g = 0, n = _d.getUint32(off + 12); g < n; g++) {
        final q = off + 16 + g * 12, s = _d.getUint32(q);
        if (cp < s) return 0;
        if (cp <= _d.getUint32(q + 4)) return _d.getUint32(q + 8) + cp - s;
      }
      return 0;
    }
    if (cp > 0xffff) return 0;
    final sc = _d.getUint16(off + 6) ~/ 2;
    final ends = off + 14, starts = ends + sc * 2 + 2;
    final deltas = starts + sc * 2, ranges = deltas + sc * 2;
    for (var s = 0; s < sc; s++) {
      if (cp > _d.getUint16(ends + s * 2)) continue;
      final st = _d.getUint16(starts + s * 2);
      if (cp < st) return 0;
      final ro = _d.getUint16(ranges + s * 2),
          dl = _d.getUint16(deltas + s * 2);
      if (ro == 0) return (cp + dl) & 0xffff;
      final g = _d.getUint16(ranges + s * 2 + ro + (cp - st) * 2);
      return g == 0 ? 0 : (g + dl) & 0xffff;
    }
    return 0;
  }

  /// `hmtx` advance (font units) of the glyph the `cmap` gives for [cp].
  int advance(int cp) => _cache.putIfAbsent(cp, () {
    final g = _glyph(cp);
    return _d.getUint16(_hmtx + (g < _nh ? g : _nh - 1) * 4);
  });
}

class TextMetrics {
  TextMetrics._(this.regular, this.bold);

  static TextMetrics? _i;

  static bool get isLoaded => _i != null;

  static TextMetrics get instance =>
      _i ?? (throw StateError('TextMetrics not loaded'));

  final FontAdvances regular, bold;

  FontAdvances font(bool bold) => bold ? this.bold : regular;

  /// Reads both font files from the app bundle (once).
  static Future<void> load() async {
    if (_i != null) return;
    final r = await rootBundle.load('assets/fonts/Pretendard-Regular.otf');
    final b = await rootBundle.load('assets/fonts/Pretendard-SemiBold.otf');
    install(
      r.buffer.asUint8List(r.offsetInBytes, r.lengthInBytes),
      b.buffer.asUint8List(b.offsetInBytes, b.lengthInBytes),
    );
  }

  /// Installs the metrics from font bytes; throws when a file is not the one
  /// named in spec/decisions/text-font.md.
  static void install(Uint8List regular, Uint8List bold) {
    if (sha256.convert(regular).toString() != _regularSha ||
        sha256.convert(bold).toString() != _boldSha) {
      throw StateError(
        'Pretendard files differ from spec/decisions/text-font.md',
      );
    }
    _i = TextMetrics._(FontAdvances.parse(regular), FontAdvances.parse(bold));
  }
}
