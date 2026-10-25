/// "Write with pen only": auto follows the stored stylus detection.
enum PenOnlyMode {
  auto,
  on,
  off;

  /// An unknown or missing name is [auto].
  static PenOnlyMode parse(String? name) => PenOnlyMode.values.firstWhere(
    (m) => m.name == name,
    orElse: () => PenOnlyMode.auto,
  );
}
