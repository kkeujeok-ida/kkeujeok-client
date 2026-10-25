/// How the pages of a note are laid out on screen: a device setting.
enum PageViewMode {
  vertical,
  horizontal,
  twoPage;

  /// [vertical] for a missing, unknown or non-string value.
  static PageViewMode parse(Object? v) => PageViewMode.values.firstWhere(
    (m) => m.name == v,
    orElse: () => PageViewMode.vertical,
  );
}
