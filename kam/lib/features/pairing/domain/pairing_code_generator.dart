import 'dart:math';

/// Generates a 130-bit human-shareable secret. Random quality comes from the
/// platform CSPRNG; Firestore rules enforce use/expiry but cannot prove entropy.
class PairingCodeGenerator {
  PairingCodeGenerator({Random? random}) : _random = random ?? Random.secure();
  final Random _random;
  static const alphabet = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';

  String generate() => List.generate(
    26,
    (_) => alphabet[_random.nextInt(alphabet.length)],
  ).join();
}
