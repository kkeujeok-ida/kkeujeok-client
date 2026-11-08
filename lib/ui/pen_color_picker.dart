import 'dart:math' as math;

import 'package:flutter/gestures.dart';

import 'kk.dart';

import 'package:flutter/material.dart';

import '../design_tokens/build/tokens.dart';
import '../l10n/app_localizations.dart';
import '../render/page_painter.dart' show parseColor;

String hexOf(Color c) {
  String h(double v) => (v * 255).round().toRadixString(16).padLeft(2, '0');
  return '#${h(c.r)}${h(c.g)}${h(c.b)}';
}

String hsvToHex(HSVColor c) => hexOf(c.toColor());

final _hex6 = RegExp(r'^#[0-9a-f]{6}$');

/// Null when [hex] is not `#rrggbb` (case ignored).
HSVColor? hexToHsv(String hex) {
  final x = hex.toLowerCase();
  return _hex6.hasMatch(x) ? HSVColor.fromColor(parseColor(x)) : null;
}

// Wheel ratios, same as the web (spec/pen.md "Color wheel"): ring 224, band 24,
// square 122; the ring's touch band reaches 48 inward (the square wins inside).
const _ring = 224.0;
const _ringWidth = 24.0;
const _side = 122.0;
const _ringHit = 48.0;

enum WheelZone { ring, square, none }

/// Where a press at [p] (in the wheel's box) lands: the square, the ring's
/// touch band (drawn band plus the hole's rim), or nowhere.
WheelZone wheelZone(Offset p) {
  const mid = Offset(_ring / 2, _ring / 2);
  final d = (p - mid).distance;
  if (d > _ring / 2) return WheelZone.none;
  if ((p - mid).dx.abs() <= _side / 2 && (p - mid).dy.abs() <= _side / 2) {
    return WheelZone.square;
  }
  return d >= _ring / 2 - _ringHit ? WheelZone.ring : WheelZone.none;
}

/// `#` is optional when typing six hex digits.
String withHash(String raw) =>
    RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(raw) ? '#$raw' : raw;

/// A pan that wins the arena at once, so a vertical drag picks a color
/// instead of scrolling the dialog.
class _EagerPan extends PanGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}

/// A hue ring with a saturation/brightness square inside and a HEX field;
/// pops `#rrggbb` (lower case) on [Apply] and null on [Cancel]. Its own
/// dialog: the content scrolls, so the HEX field stays above the keyboard.
Future<String?> showPenColorPicker(BuildContext context, String initial) =>
    showDialog<String>(
      context: context,
      builder: (_) => _PenColorPicker(initial),
    );

class _PenColorPicker extends StatefulWidget {
  const _PenColorPicker(this.initial);

  final String initial;

  @override
  State<_PenColorPicker> createState() => _PenColorPickerState();
}

class _PenColorPickerState extends State<_PenColorPicker> {
  late HSVColor _c = HSVColor.fromColor(parseColor(widget.initial));
  bool _touched = false; // untouched: Apply returns the initial hex as is
  String? _typed; // a valid typed hex, used as is (no HSV round trip)
  late final _field = TextEditingController(text: widget.initial.toLowerCase());
  WheelZone _zone = WheelZone.none;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _resetField();
    });
  }

  // A rejected or partial entry goes back to the current valid hex.
  void _resetField() => _field.text = _typed ?? hsvToHex(_c);

  @override
  void dispose() {
    _focus.dispose();
    _field.dispose();
    super.dispose();
  }

  void _set(HSVColor c) {
    setState(() {
      _touched = true;
      _typed = null;
      _c = c;
      _field.text = hsvToHex(c);
    });
  }

  void _down(Offset p) {
    _zone = wheelZone(p);
    _drag(p);
  }

  void _drag(Offset p) {
    const mid = Offset(_ring / 2, _ring / 2);
    if (_zone == WheelZone.none) return;
    if (_zone == WheelZone.ring) {
      final a = math.atan2(p.dy - mid.dy, p.dx - mid.dx) * 180 / math.pi + 90;
      _set(_c.withHue((a + 360) % 360));
    } else {
      final q = p - mid + const Offset(_side / 2, _side / 2);
      _set(
        _c
            .withSaturation((q.dx / _side).clamp(0.0, 1.0))
            .withValue(1 - (q.dy / _side).clamp(0.0, 1.0)),
      );
    }
  }

  void _typeHex(String raw) {
    raw = withHash(raw);
    final c = hexToHsv(raw);
    if (c == null) return; // rejected: the last color stays
    setState(() {
      _touched = true;
      _typed = raw.toLowerCase();
      // gray/black: the hue stays where it was
      _c = c.saturation == 0 || c.value == 0 ? c.withHue(_c.hue) : c;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hex = _typed ?? hsvToHex(_c);
    return AlertDialog(
      backgroundColor: Kk.componentsPopoverBackground,
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Semantics(
              label:
                  '${l10n.colorHue} / ${l10n.colorSaturation} / '
                  '${l10n.colorBrightness} ${hex.toUpperCase()}',
              child: RawGestureDetector(
                gestures: {
                  _EagerPan: GestureRecognizerFactoryWithHandlers<_EagerPan>(
                    _EagerPan.new,
                    (g) => g
                      ..onDown = ((d) => _down(d.localPosition))
                      ..onUpdate = ((d) => _drag(d.localPosition)),
                  ),
                },
                child: CustomPaint(
                  size: const Size.square(_ring),
                  painter: _WheelPainter(_c),
                ),
              ),
            ),
          ),
          const SizedBox(height: KkjTokens.spacing3),
          Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: parseColor(hex),
                  borderRadius: BorderRadius.circular(KkjTokens.roundedSm),
                  border: Border.all(color: Kk.colorBorderControl),
                ),
                child: const SizedBox.square(dimension: 40),
              ),
              const SizedBox(width: KkjTokens.spacing3),
              Expanded(
                child: TextField(
                  controller: _field,
                  focusNode: _focus,
                  maxLength: 7,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'HEX',
                    counterText: '',
                  ),
                  onChanged: _typeHex,
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.colorPickerCancel),
        ),
        TextButton(
          onPressed: () {
            _resetField();
            Navigator.of(context)
                .pop(_touched ? hex : widget.initial.toLowerCase());
          },
          child: Text(l10n.colorPickerApply),
        ),
      ],
    );
  }
}

class _WheelPainter extends CustomPainter {
  _WheelPainter(this.c);

  final HSVColor c;

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.center(Offset.zero);
    final r = _ring / 2 - _ringWidth / 2;
    canvas.drawCircle(
      mid,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _ringWidth
        ..shader = SweepGradient(
          colors: [
            for (var i = 0; i <= 6; i++)
              HSVColor.fromAHSV(1, i * 60.0 % 360, 1, 1).toColor(),
          ],
          transform: const GradientRotation(-math.pi / 2),
        ).createShader(Rect.fromCircle(center: mid, radius: r)),
    );
    final sq = Rect.fromCenter(center: mid, width: _side, height: _side);
    final hue = HSVColor.fromAHSV(1, c.hue, 1, 1).toColor();
    canvas.drawRect(
      sq,
      Paint()
        ..shader = LinearGradient(colors: [Colors.white, hue]).createShader(sq),
    );
    canvas.drawRect(
      sq,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black, Color(0x00000000)],
        ).createShader(sq),
    );
    void thumb(Offset o, Color fill) {
      canvas.drawCircle(o, 11, Paint()..color = fill);
      canvas.drawCircle(
        o,
        11,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = Colors.white,
      );
      canvas.drawCircle(
        o,
        12.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = const Color(0x80000000),
      );
    }

    final a = (c.hue - 90) * math.pi / 180;
    thumb(mid + Offset(math.cos(a), math.sin(a)) * r, hue);
    thumb(
      sq.topLeft + Offset(c.saturation * _side, (1 - c.value) * _side),
      c.toColor(),
    );
  }

  @override
  bool shouldRepaint(_WheelPainter old) => old.c != c;
}
