import 'package:flutter/material.dart';

import '../../core/constants/app_spacing.dart';

/// Builds the application theme.
///
/// Typography strategy: use the Material 3 `TextTheme` from `Theme.of(context)`
/// (via `titleMedium`, `bodyMedium`, and so on) rather than hard-coded sizes, so
/// system text scaling and accessibility settings keep working (SRS NFR-028).
///
/// Accessibility: state is always conveyed by text or icon as well as colour;
/// the theme only provides the palette.
ThemeData buildAppTheme() {
  final colorScheme = ColorScheme.fromSeed(seedColor: const Color(0xFF3B6E8F));
  final outline = OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppSpacing.radius),
  );

  return ThemeData(
    colorScheme: colorScheme,
    useMaterial3: true,
    visualDensity: VisualDensity.standard,
    scaffoldBackgroundColor: colorScheme.surface,
    inputDecorationTheme: InputDecorationTheme(
      border: outline,
      enabledBorder: outline.copyWith(
        borderSide: BorderSide(color: colorScheme.outlineVariant),
      ),
      focusedBorder: outline.copyWith(
        borderSide: BorderSide(color: colorScheme.primary, width: 2),
      ),
      errorBorder: outline.copyWith(
        borderSide: BorderSide(color: colorScheme.error),
      ),
      focusedErrorBorder: outline.copyWith(
        borderSide: BorderSide(color: colorScheme.error, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
    ),
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: colorScheme.surface,
      foregroundColor: colorScheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 1,
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
    ),
  );
}
