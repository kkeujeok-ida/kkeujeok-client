import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

/// Folder icon colors; a folder stores only the index. null = default ink.
const folderPalette = <Color>[
  Color(0xFFE5484D),
  Color(0xFFF76B15),
  Color(0xFFF5B800),
  Color(0xFF30A46C),
  Color(0xFF12A594),
  Color(0xFF0090FF),
  Color(0xFF8E4EC6),
  Color(0xFFE93D82),
];

class FolderColorsNotifier extends Notifier<Map<String, int>> {
  @override
  Map<String, int> build() =>
      ref.read(penSlotsStoreProvider).readFolderColors();

  /// [index] null clears the color.
  void set(String folderId, int? index) {
    final m = {...state};
    index == null ? m.remove(folderId) : m[folderId] = index;
    state = m;
    ref.read(penSlotsStoreProvider).writeFolderColors(m);
  }
}

final folderColorsProvider =
    NotifierProvider<FolderColorsNotifier, Map<String, int>>(
      FolderColorsNotifier.new,
    );
