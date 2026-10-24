import 'package:flutter/material.dart';

import '../model/note.dart' show copyJsonValue, jsonEqual;
import '../model/text_layout.dart';
import '../render/page_painter.dart' show parseColor;
import '../render/text_painter.dart' show textFontFamily;

typedef Style = Map<String, dynamic>;

const _known = {'size', 'color', 'bold', 'italic'};

/// The text of a box being edited with a style (the run properties) per code
/// point. Typing takes the style of the character before the caret (or the
/// one just picked in the format bar); the runs are read back at the end.
class StyledTextController extends TextEditingController {
  StyledTextController({
    required String text,
    required List runs,
    required this.base,
    this.scale = 1,
  }) : _styles = styleList(runs, cpLen(text)),
       super(text: text);

  /// The element defaults: `size`, `color`, `bold`, `italic`, all set.
  final Style base;

  /// Screen pixels per page point.
  double scale;

  List<Style> _styles;

  /// A style picked with nothing selected: it applies to what is typed next.
  Style? pending;

  List<int> get _cps => text.runes.toList();

  int _cpIndex(int utf16) =>
      text.substring(0, utf16.clamp(0, text.length)).runes.length;

  Style _at(int cp) => cp >= 0 && cp < _styles.length ? _styles[cp] : const {};

  (int, int) get _range {
    final s = selection;
    if (!s.isValid) return (0, 0);
    final a = _cpIndex(s.start), b = _cpIndex(s.end);
    return (a, b);
  }

  @override
  set value(TextEditingValue v) {
    if (v.text != text) {
      _retarget(text, v.text);
    } else if (v.selection != selection) {
      pending = null; // the caret moved
    }
    super.value = v;
  }

  void _retarget(String oldText, String newText) {
    final a = oldText.runes.toList(), b = newText.runes.toList();
    var p = 0;
    while (p < a.length && p < b.length && a[p] == b[p]) {
      p++;
    }
    var s = 0;
    while (s < a.length - p &&
        s < b.length - p &&
        a[a.length - 1 - s] == b[b.length - 1 - s]) {
      s++;
    }
    final removed = a.length - p - s, inserted = b.length - p - s;
    final Style typing =
        pending ?? (removed > 0 ? _at(p) : (p > 0 ? _at(p - 1) : const {}));
    _styles = [
      ..._styles.take(p),
      for (var i = 0; i < inserted; i++) typing,
      ..._styles.skip(a.length - s),
    ];
  }

  Object? _value(Style st, String key) =>
      st.containsKey(key) ? st[key] : base[key];

  /// The value of [key] at the caret, or on the whole selection when every
  /// character agrees (else the first one's).
  Object? valueOf(String key) {
    final (a, b) = _range;
    if (a == b) return _value(pending ?? _at(a - 1), key);
    return _value(_at(a), key);
  }

  /// True when [key] (`bold`/`italic`) holds on the whole selection or, with
  /// no selection, at the caret.
  bool isOn(String key) {
    final (a, b) = _range;
    if (a == b) return _value(pending ?? _at(a - 1), key) == true;
    for (var i = a; i < b; i++) {
      if (_value(_at(i), key) != true) return false;
    }
    return true;
  }

  void toggle(String key) => apply(key, !isOn(key));

  /// Sets [key] on the selected characters; with no selection on the text
  /// typed next.
  void apply(String key, Object value) {
    final (a, b) = _range;
    if (a == b) {
      pending = {...(pending ?? _at(a - 1)), key: value};
    } else {
      _styles = [
        for (var i = 0; i < _styles.length; i++)
          i >= a && i < b ? {..._styles[i], key: value} : _styles[i],
      ];
    }
    notifyListeners();
  }

  /// The runs to store: properties equal to the element defaults dropped,
  /// then the normal form of spec/text.md.
  List<Map<String, dynamic>> get runs {
    final out = <Style>[];
    for (var i = 0; i < _styles.length; i++) {
      final st = {
        for (final e in _styles[i].entries)
          if (!(_known.contains(e.key) && jsonEqual(e.value, base[e.key])))
            e.key: copyJsonValue(e.value),
      };
      if (st.isNotEmpty) out.add({'start': i, 'end': i + 1, ...st});
    }
    return normalizeRuns(out, _styles.length);
  }

  TextStyle _textStyle(Style st, TextStyle? outer) {
    final v = _value(st, 'size');
    final size = v is num && v.isFinite
        ? v.toDouble().clamp(sizeMin, sizeMax)
        : sizeDefault;
    return (outer ?? const TextStyle()).copyWith(
      fontFamily: textFontFamily,
      fontSize: size * scale,
      height: lineHeight,
      color: parseColor(_value(st, 'color')),
      fontWeight: _value(st, 'bold') == true
          ? FontWeight.w600
          : FontWeight.w400,
      fontStyle: _value(st, 'italic') == true
          ? FontStyle.italic
          : FontStyle.normal,
    );
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final cps = _cps;
    final spans = <TextSpan>[];
    var i = 0;
    while (i < cps.length) {
      var j = i + 1;
      while (j < cps.length && jsonEqual(_at(j), _at(i))) {
        j++;
      }
      spans.add(
        TextSpan(
          text: String.fromCharCodes(cps.sublist(i, j)),
          style: _textStyle(_at(i), style),
        ),
      );
      i = j;
    }
    return TextSpan(style: _textStyle(const {}, style), children: spans);
  }

  /// The code point index of the caret (the end of the selection).
  int get caretCp =>
      selection.isValid ? _cpIndex(selection.extentOffset) : cpLen(text);
}
