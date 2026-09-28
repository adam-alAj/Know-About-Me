import 'dart:math';

/// Generates opaque, path-safe rule identifiers.
///
/// A rule id is a document id, so it must never contain `/`. Identifiers are
/// client-generated because the Spark-only architecture has no server to mint
/// them; they carry no authority, so guessing one grants nothing — the Firestore
/// rules authorize every read and write by authenticated identity, not by id
/// (ADR-009).
class RuleIdGenerator {
  RuleIdGenerator({Random? random}) : _random = random ?? Random.secure();

  /// Character set used for generated ids. Lowercase alphanumerics keep ids
  /// copy-safe and Firestore-path-safe.
  static const String alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';

  /// Length chosen to match the pairing code entropy class.
  static const int length = 20;

  final Random _random;

  String generate() => List<String>.generate(
    length,
    (_) => alphabet[_random.nextInt(alphabet.length)],
  ).join();
}
