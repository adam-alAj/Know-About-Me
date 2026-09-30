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

  /// Between-section separation on a long screen. Larger than [xl] so the eye
  /// can group sections without a divider or a heavier surface.
  static const double xxl = 40;

  /// Corner radius for cards and controls.
  static const double radius = 12;
}

/// Corner radii (SRS Task 12).
///
/// A deliberately small set: controls and small containers use [sm], cards and
/// sheets use [md] (the historical [AppSpacing.radius] value, kept so existing
/// layouts are unchanged), and large surfaces such as the map use [lg].
abstract final class AppRadius {
  /// Small controls, chips and inline status pills.
  static const double sm = 8;

  /// Cards, dialogs and text fields.
  static const double md = 12;

  /// Large surfaces: map viewports, hero panels.
  static const double lg = 16;
}

/// Fixed durations used by the UI.
abstract final class AppDurations {
  /// Short transition, for example a status chip changing.
  static const Duration short = Duration(milliseconds: 150);

  /// Medium transition, for example a state view cross-fading.
  static const Duration medium = Duration(milliseconds: 300);
}
