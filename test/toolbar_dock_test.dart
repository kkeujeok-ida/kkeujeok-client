import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/model/toolbar_pos.dart';
import 'package:kkeujeok/ui/toolbar_dock.dart';

const _win = Size(900, 700);
const _bar = Size(455, 34);
const _vbar = Size(48, 400);
const _none = EdgeInsets.zero;

void main() {
  group('dockAtPointer', () {
    // Top outline: x 222.5..677.5, y 12..46.
    test('48 is in, 47.9 in, 48.1 out (distance to the rectangle)', () {
      expect(
        dockAtPointer(
          const Offset(450, 94),
          _bar,
          _win,
          _none,
          vertical: _vbar,
        ),
        ToolbarDock.top,
      );
      expect(
        dockAtPointer(
          const Offset(450, 93.9),
          _bar,
          _win,
          _none,
          vertical: _vbar,
        ),
        ToolbarDock.top,
      );
      expect(
        dockAtPointer(
          const Offset(450, 94.1),
          _bar,
          _win,
          _none,
          vertical: _vbar,
        ),
        isNull,
      );
    });

    test('a bar wider than the radius still docks by its rectangle edge', () {
      // Far from the top outline center, but on the outline itself.
      expect(
        dockAtPointer(
          const Offset(300, 30),
          _bar,
          _win,
          _none,
          vertical: _vbar,
        ),
        ToolbarDock.top,
      );
    });

    test('left and right use the vertical size', () {
      // Left outline: x 12..60, y 150..550.
      expect(
        dockAtPointer(
          const Offset(100, 300),
          _bar,
          _win,
          _none,
          vertical: _vbar,
        ),
        ToolbarDock.left,
      );
      expect(
        dockAtPointer(
          const Offset(100, 150),
          _bar,
          _win,
          _none,
          vertical: _vbar,
        ),
        ToolbarDock.left,
      );
      expect(
        dockAtPointer(
          const Offset(808, 560),
          _bar,
          _win,
          _none,
          vertical: _vbar,
        ),
        ToolbarDock.right,
      );
      expect(
        dockAtPointer(
          const Offset(100, 603),
          _bar,
          _win,
          _none,
          vertical: _vbar,
        ),
        isNull,
      );
    });

    test('pointer at the left edge docks left even for a wide bar', () {
      expect(
        dockAtPointer(const Offset(2, 300), _bar, _win, _none, vertical: _vbar),
        ToolbarDock.left,
      );
      expect(
        dockAtPointer(
          const Offset(450, 350),
          _bar,
          _win,
          _none,
          vertical: _vbar,
        ),
        isNull,
      );
    });

    test('overlap: snapOrder first wins', () {
      // A tiny screen where every outline touches the center.
      const win = Size(100, 100);
      const bar = Size(200, 200);
      expect(
        dockAtPointer(const Offset(50, 50), bar, win, _none),
        ToolbarDock.top,
      );
    });

    test('safe area moves the outlines', () {
      const inset = EdgeInsets.only(left: 40);
      final r = dockRect(ToolbarDock.left, _vbar, _win, inset);
      expect(r.left, 40 + 12);
    });
  });

  group('centerOf', () {
    test('float is clamped for display and the pos is not changed', () {
      final pos = ToolbarPos.floating(1, 0, vertical: false);
      final c = centerOf(pos, _bar, _win, _none);
      expect(c.dx, 900 - 12 - 455 / 2);
      expect(c.dy, 12 + 17);
      expect(pos.x, 1); // untouched
      // A bigger screen gives the stored ratio back.
      expect(
        centerOf(pos, _bar, const Size(2000, 700), _none).dx,
        2000 - 12 - 455 / 2,
      );
      final mid = ToolbarPos.floating(0.5, 0.5, vertical: false);
      expect(centerOf(mid, _bar, _win, _none), const Offset(450, 350));
    });

    test('docked bars are centered on their edge', () {
      expect(
        centerOf(const ToolbarPos(dock: ToolbarDock.bottom), _bar, _win, _none),
        Offset(450, 700 - 12 - 17),
      );
      expect(
        centerOf(
          const ToolbarPos(dock: ToolbarDock.left, vertical: true),
          _vbar,
          _win,
          _none,
        ),
        const Offset(12 + 24, 350),
      );
    });
  });

  test('ratioOf and topFits', () {
    expect(ratioOf(const Offset(225, 350), _win), const Offset(0.25, 0.5));
    expect(ratioOf(const Offset(-5, 900), _win), const Offset(0, 1));
    expect(topFits(503, 359), isTrue);
    expect(topFits(502, 359), isFalse);
  });

  group('ToolbarPos', () {
    test('applyDock sets vertical from the dock; float keeps it', () {
      const p = ToolbarPos();
      expect(p.applyDock(ToolbarDock.left).vertical, isTrue);
      expect(p.applyDock(ToolbarDock.right).vertical, isTrue);
      expect(p.applyDock(ToolbarDock.bottom).vertical, isFalse);
      final v = const ToolbarPos(dock: ToolbarDock.left, vertical: true);
      expect(v.applyDock(ToolbarDock.float).vertical, isTrue);
      expect(v.applyDock(ToolbarDock.float).dock, ToolbarDock.float);
    });

    test('floating rounds the ratio to 4 digits', () {
      final p = ToolbarPos.floating(0.123456, 0.987654, vertical: false);
      expect((p.x, p.y), (0.1235, 0.9877));
    });

    test('parse: invalid values give the default', () {
      const ok = {'dock': 'float', 'x': 0.2, 'y': 0.7, 'vertical': true};
      final p = ToolbarPos.parse(ok);
      expect(
        (p.dock, p.x, p.y, p.vertical),
        (ToolbarDock.float, 0.2, 0.7, true),
      );
      expect(ToolbarPos.parse(p.toJson()), p);
      for (final bad in <Object?>[
        null,
        'x',
        {...ok, 'dock': 'middle'},
        {...ok, 'dock': 3},
        {...ok, 'x': 1.5},
        {...ok, 'y': -0.1},
        {...ok, 'x': '0.2'},
        {...ok, 'y': null},
        {...ok, 'vertical': 1},
        {'dock': 'top'},
      ]) {
        expect(ToolbarPos.parse(bad), ToolbarPos.defaults, reason: '$bad');
      }
    });

    test('a docked position takes vertical from its dock', () {
      final p = ToolbarPos.parse({
        'dock': 'left',
        'x': 0.5,
        'y': 0,
        'vertical': false,
      });
      expect(p.vertical, isTrue);
      final q = ToolbarPos.parse({
        'dock': 'top',
        'x': 0.5,
        'y': 0,
        'vertical': true,
      });
      expect(q.vertical, isFalse);
    });
  });
}
