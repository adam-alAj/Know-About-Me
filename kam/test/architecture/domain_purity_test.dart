import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Architecture tests that enforce the dependency rules described in
/// `docs/architecture/ARCHITECTURE.md` §2.
///
/// These are the boundaries that cannot be expressed in the type system, so they
/// are verified mechanically instead of relying on review alone. Only real
/// `import`/`export` directives are inspected, so documentation may still
/// mention a path without failing the build.
void main() {
  List<File> dartFilesIn(String directory) {
    final dir = Directory(directory);
    if (!dir.existsSync()) return const <File>[];
    return dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList();
  }

  String normalized(File file) => file.path.replaceAll(r'\', '/');

  /// The `import`/`export` targets declared by [file].
  List<String> dependencyTargets(File file) {
    final pattern = RegExp(r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''');
    return file
        .readAsLinesSync()
        .map((line) => pattern.firstMatch(line)?.group(1))
        .whereType<String>()
        .toList();
  }

  test('feature domain layers stay pure Dart', () {
    final domainFiles = dartFilesIn(
      'lib/features',
    ).where((file) => normalized(file).contains('/domain/')).toList();

    expect(
      domainFiles,
      isNotEmpty,
      reason: 'Expected feature domain models to exist',
    );

    const forbiddenPrefixes = <String>[
      'package:flutter/',
      'package:flutter_riverpod/',
      'package:firebase',
      'package:cloud_firestore',
      'package:go_router/',
      'dart:ui',
    ];

    for (final file in domainFiles) {
      for (final target in dependencyTargets(file)) {
        for (final forbidden in forbiddenPrefixes) {
          expect(
            target.startsWith(forbidden),
            isFalse,
            reason:
                '${normalized(file)} must not depend on "$target" '
                '(domain layers are pure Dart)',
          );
        }
      }
    }
  });

  test('core never depends on a feature', () {
    final coreFiles = dartFilesIn('lib/core');
    expect(coreFiles, isNotEmpty);

    for (final file in coreFiles) {
      for (final target in dependencyTargets(file)) {
        expect(
          target.contains('features/'),
          isFalse,
          reason: '${normalized(file)} must not import a feature ($target)',
        );
      }
    }
  });

  test('Firebase SDKs are only imported at the allowed boundaries', () {
    final libFiles = dartFilesIn('lib');
    expect(libFiles, isNotEmpty);

    const firebasePackages = <String>[
      'package:firebase_core',
      'package:firebase_auth',
      'package:cloud_firestore',
      'package:firebase_messaging',
      'package:cloud_functions',
    ];

    // Phase 3 introduces Firebase, but only behind the boundaries recorded in
    // docs/decisions/ADR-007-firebase-integration.md:
    //   - core/firebase/            (initialization, options, error mapping)
    //   - features/<f>/data/        (repositories and data sources)
    // Firebase must never appear in a feature's domain or presentation layer, and
    // never in shared UI.
    bool isAllowedBoundary(String path) =>
        path.contains('/core/firebase/') ||
        RegExp(r'/features/[^/]+/data/').hasMatch(path);

    for (final file in libFiles) {
      final path = normalized(file);
      for (final target in dependencyTargets(file)) {
        if (firebasePackages.any(target.startsWith)) {
          expect(
            isAllowedBoundary(path),
            isTrue,
            reason:
                '$path imports $target; Firebase SDKs are only allowed in '
                'core/firebase/ and features/*/data/ (ADR-007)',
          );
        }
      }
    }
  });
}
