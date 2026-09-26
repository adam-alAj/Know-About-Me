import '../../../../core/error/app_failure.dart';
import '../models/app_user.dart';

/// Validates user-entered credentials and profile fields.
///
/// Pure Dart and side-effect free, so it is usable directly as a
/// `TextFormField.validator` **and** unit-testable without a widget tree. Both
/// paths must agree, otherwise a value can pass the form and still be rejected by
/// the Security Rules.
///
/// Rules are deliberately conservative and never echo the rejected value back
/// (that could place a password in a log or a UI string).
abstract final class AuthInputValidation {
  /// Minimum password length enforced by the client.
  ///
  /// Firebase Authentication itself accepts 6; the product requires a stronger
  /// floor (SRS NFR-001). Documented in
  /// `docs/architecture/AUTHENTICATION_ARCHITECTURE.md` §7.
  static const int minimumPasswordLength = 8;

  /// Upper bound for a display name. Must equal the bound enforced by
  /// `firebase/firestore.rules` for `users/{uid}.displayName`.
  static const int maximumDisplayNameLength = AppUser.maxDisplayNameLength;

  /// Pragmatic address check: one `@`, a domain, and a dot in the domain.
  ///
  /// Not RFC 5322: a fully correct email grammar would reject addresses real
  /// users own. The authoritative validation is Firebase Authentication's.
  static final RegExp _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$');

  /// Returns a user-safe message, or `null` when [value] is acceptable.
  static String? email(String? value) {
    final trimmed = (value ?? '').trim();
    if (trimmed.isEmpty) return 'Enter your email address.';
    if (!_email.hasMatch(trimmed)) return 'Enter a valid email address.';
    return null;
  }

  /// Returns a user-safe message, or `null` when [value] is acceptable.
  static String? password(String? value) {
    final password = value ?? '';
    if (password.isEmpty) return 'Enter your password.';
    if (password.length < minimumPasswordLength) {
      return 'Use at least $minimumPasswordLength characters.';
    }
    return null;
  }

  /// Checks a confirmation field against [password].
  static String? confirmPassword(String? value, {required String password}) {
    if ((value ?? '').isEmpty) return 'Re-enter your password.';
    if (value != password) return 'The passwords do not match.';
    return null;
  }

  /// Returns a user-safe message, or `null` when [value] is acceptable.
  static String? displayName(String? value) {
    final trimmed = (value ?? '').trim();
    if (trimmed.isEmpty) return 'Enter a name to display.';
    if (trimmed.length > maximumDisplayNameLength) {
      return 'Use $maximumDisplayNameLength characters or fewer.';
    }
    return null;
  }

  /// Converts the first failing rule into a [ValidationFailure].
  ///
  /// Returns `null` when every supplied check passes, so the caller can
  /// short-circuit before touching the network.
  static ValidationFailure? firstFailure(Iterable<String?> messages) {
    for (final message in messages) {
      if (message != null) return ValidationFailure(message);
    }
    return null;
  }
}
