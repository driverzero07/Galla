/// Switches for features that are built but not ready to ship.
abstract final class FeatureFlags {
  /// Photo of the paper copy read by a vision model (Part 6). OFF in v1: the
  /// code is in place but the option is hidden and nothing is ever sent.
  static const ocrImport = false;
}
