/// Shared spacing scale (SRS Task 12: spacing conventions).
///
/// Features must use these values instead of literal numbers so the
/// reassurance-oriented layout stays calm and consistent, and so global density
/// changes remain possible.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;

  /// Corner radius for cards and controls.
  static const double radius = 12;
}

/// Fixed durations used by the UI.
abstract final class AppDurations {
  /// Short transition, for example a status chip changing.
  static const Duration short = Duration(milliseconds: 150);

  /// Medium transition, for example a state view cross-fading.
  static const Duration medium = Duration(milliseconds: 300);
}
