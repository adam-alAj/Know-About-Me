import 'package:flutter/material.dart';

/// A labelled single-choice control.
///
/// Built on `DropdownButton` inside an [InputDecorator] rather than
/// `DropdownButtonFormField`, so the current selection is always the value the
/// domain model holds (never a stale widget-local copy) and the control stays
/// readable by assistive technology with a real label and error text.
class RuleChoiceField<T> extends StatelessWidget {
  const RuleChoiceField({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.errorText,
    this.helperText,
  });

  /// Visible field label.
  final String label;

  /// Currently selected value, or `null` when nothing is chosen yet.
  final T? value;

  /// Selectable `(value, label)` pairs.
  final List<(T, String)> options;

  /// Called with the newly selected value.
  final ValueChanged<T> onChanged;

  /// Error text shown beneath the control.
  final String? errorText;

  /// Optional supporting text.
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        errorText: errorText,
        helperText: helperText,
      ),
      // The selected value is always present in `options`; a defensive fallback
      // keeps a corrupt value from crashing the field.
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          isExpanded: true,
          value: options.any((option) => option.$1 == value) ? value : null,
          hint: const Text('Choose'),
          items: [
            for (final option in options)
              DropdownMenuItem<T>(value: option.$1, child: Text(option.$2)),
          ],
          onChanged: (selected) {
            if (selected != null) onChanged(selected);
          },
        ),
      ),
    );
  }
}
