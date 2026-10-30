import 'dart:convert';

enum LibraryLayout { grid, list }

enum LibrarySize { small, standard, large }

/// How the note list is shown: layout x thumbnail size. The default, a large
/// list, is the original card flow.
class LibraryView {
  const LibraryView(this.layout, this.size);

  static const defaults = LibraryView(LibraryLayout.list, LibrarySize.large);

  final LibraryLayout layout;
  final LibrarySize size;

  /// Anything but `{"layout":..,"size":..}` with known names is [defaults].
  static LibraryView parse(Object? raw) {
    try {
      final m = jsonDecode(raw as String) as Map;
      final l = LibraryLayout.values.byName(m['layout'] as String);
      final s = LibrarySize.values.byName(m['size'] as String);
      return LibraryView(l, s);
    } catch (_) {
      return defaults;
    }
  }

  String encode() => jsonEncode({'layout': layout.name, 'size': size.name});

  @override
  bool operator ==(Object other) =>
      other is LibraryView && other.layout == layout && other.size == size;

  @override
  int get hashCode => Object.hash(layout, size);
}
