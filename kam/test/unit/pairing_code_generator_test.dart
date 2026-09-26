import 'package:flutter_test/flutter_test.dart';
import 'package:kam/features/pairing/domain/pairing_code_generator.dart';

void main() {
  test('generates a 26 character code from the approved alphabet', () {
    final code = PairingCodeGenerator().generate();
    expect(code, hasLength(26));
    expect(
      code.codeUnits.every(
        (unit) => PairingCodeGenerator.alphabet.contains(String.fromCharCode(unit)),
      ),
      isTrue,
    );
  });

  test('independent generated codes differ', () {
    final generator = PairingCodeGenerator();
    final codes = List.generate(100, (_) => generator.generate());
    expect(codes.toSet(), hasLength(codes.length));
  });
}
