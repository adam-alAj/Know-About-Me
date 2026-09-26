import 'package:flutter/material.dart';

/// Emphasis of an [AppButton].
enum AppButtonVariant { primary, secondary, text }

/// Shared button so action emphasis stays consistent across features.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.icon,
  });

  /// A filled, high-emphasis action.
  const AppButton.primary({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  }) : variant = AppButtonVariant.primary;

  /// An outlined, medium-emphasis action.
  const AppButton.secondary({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  }) : variant = AppButtonVariant.secondary;

  /// Button text.
  final String label;

  /// Tap handler; null disables the button.
  final VoidCallback? onPressed;

  /// Visual emphasis.
  final AppButtonVariant variant;

  /// Optional leading icon.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final child = icon == null
        ? Text(label)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 8),
              Text(label),
            ],
          );

    return switch (variant) {
      AppButtonVariant.primary => FilledButton(
        onPressed: onPressed,
        child: child,
      ),
      AppButtonVariant.secondary => OutlinedButton(
        onPressed: onPressed,
        child: child,
      ),
      AppButtonVariant.text => TextButton(onPressed: onPressed, child: child),
    };
  }
}
