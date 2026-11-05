import 'package:flutter/material.dart';

const _menuWidth = 200.0;

/// `PopupMenuButton` offset and menu constraints for the left-handed setting:
/// the menu extends to the left of its button instead of to the right.
/// shortcut: a fixed menu width (long labels wrap), since a popup cannot be
/// measured before it opens.
({Offset offset, BoxConstraints? constraints}) handedMenu(
  bool leftHanded,
  double buttonWidth,
) => leftHanded
    ? (
        offset: Offset(buttonWidth - _menuWidth, 0),
        constraints: const BoxConstraints.tightFor(width: _menuWidth),
      )
    : (offset: Offset.zero, constraints: null);
