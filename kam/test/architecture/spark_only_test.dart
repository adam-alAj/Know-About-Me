import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Enforces the Spark-only architecture decision (ADR-009).
///
/// The project must remain deployable on the Firebase Spark (no-cost) plan with
/// no Cloud Billing account. These checks make that a property the build
/// verifies, rather than a promise in a document: a future change that adds a
/// Functions dependency, a privileged credential or a server-only assumption
/// fails here.
///
/// See `docs/architecture/SPARK_ONLY_ARCHITECTURE.md` and
/// `docs/SPARK_COMPATIBILITY_CHECKLIST.md`.
void main() {
  String normalized(File file) => file.path.replaceAll(r'\', '/');

  /// Files under [directory], excluding build output and dependencies.
  List<File> sourceFilesIn(String directory) {
    final dir = Directory(directory);
    if (!dir.existsSync()) return const <File>[];
    const excluded = <String>[
      '/node_modules/',
      '/build/',
      '/.dart_tool/',
      '/.gradle/',
      '/.git/',
    ];
    return dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => !excluded.any(normalized(file).contains))
        .toList();
  }

  List<File> dartFilesIn(String directory) => sourceFilesIn(
    directory,
  ).where((file) => file.path.endsWith('.dart')).toList();

  /// The file's text, or `null` when it is not valid UTF-8 (a build artifact
  /// such as a Gradle lock file), which a text scan must skip.
  String? textOf(File file) {
    try {
      return utf8.decode(file.readAsBytesSync());
    } on FormatException {
      return null;
    }
  }

  /// The `import`/`export` targets declared by [file].
  List<String> dependencyTargets(File file) {
    final pattern = RegExp(r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''');
    return file
        .readAsLinesSync()
        .map((line) => pattern.firstMatch(line)?.group(1))
        .whereType<String>()
        .toList();
  }

  test('no Cloud Functions client or Admin SDK is imported anywhere', () {
    // Only real import directives are inspected, so documentation may still
    // explain why Functions are unsuitable without failing the build.
    const forbiddenPackages = <String>[
      'package:cloud_functions/',
      'package:firebase_functions/',
      'package:firebase_admin/',
    ];

    final files = [...dartFilesIn('lib'), ...dartFilesIn('test')];
    expect(files, isNotEmpty);

    for (final file in files) {
      for (final target in dependencyTargets(file)) {
        for (final forbidden in forbiddenPackages) {
          expect(
            target.startsWith(forbidden),
            isFalse,
            reason:
                '${normalized(file)} imports $target; the Spark-only '
                'architecture forbids Cloud Functions and the Admin SDK '
                '(ADR-009)',
          );
        }
      }
    }
  });

  test('pubspec declares no Functions or Admin dependency', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final banned in <String>[
      'cloud_functions',
      'firebase_functions',
      'firebase_admin',
    ]) {
      expect(
        pubspec.contains(banned),
        isFalse,
        reason: 'pubspec.yaml must not depend on $banned (ADR-009)',
      );
    }
  });

  test('firebase.json declares no billing-required deploy target', () {
    final config =
        jsonDecode(File('firebase.json').readAsStringSync())
            as Map<String, dynamic>;

    // `firestore` and `emulators` are Spark-compatible. A `functions` deploy
    // target is exactly what would require the Blaze plan, and Extensions
    // routinely require Cloud Functions, so both are rejected by default.
    expect(
      config.containsKey('functions'),
      isFalse,
      reason: 'A "functions" block makes deployment require the Blaze plan',
    );
    expect(
      config.containsKey('extensions'),
      isFalse,
      reason: 'Extensions commonly require Cloud Functions (billing)',
    );
    expect(config.containsKey('firestore'), isTrue);
  });

  test(
    'unused FCM client SDK stays out until notification delivery is designed',
    () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(
        pubspec.contains('firebase_messaging'),
        isFalse,
        reason:
            'Remote push has no trusted sender under Spark; do not ship an unused FCM SDK',
      );
    },
  );

  test('no privileged credential is present anywhere it could ship', () {
    // Privileged (server-only) credential shapes. Client-safe Firebase
    // identifiers such as an API key are deliberately NOT in this list: the
    // project distinguishes the two, and a config identifier is not a secret
    // (see docs/architecture/FIREBASE_SECURITY.md).
    const privilegedPatterns = <String>[
      'BEGIN PRIVATE KEY',
      'BEGIN RSA PRIVATE KEY',
      '"type": "service_account"',
      'firebase-adminsdk',
      'firebase-admin',
      'FCM_SERVER_KEY',
      'fcmServerKey',
    ];

    // Scanned where a secret could actually leak into the app or the repo.
    final roots = <String>['lib', 'test', 'firebase', 'android', 'ios'];

    for (final root in roots) {
      for (final file in sourceFilesIn(root)) {
        // This file necessarily contains the patterns it searches for, so it
        // cannot scan itself without always failing.
        if (normalized(
          file,
        ).endsWith('test/architecture/spark_only_test.dart')) {
          continue;
        }
        // Skip binary-ish and generated artifacts.
        if (file.path.endsWith('.png') ||
            file.path.endsWith('.jpg') ||
            file.path.endsWith('.jar') ||
            file.path.endsWith('.keystore') ||
            file.path.endsWith('.jks')) {
          continue;
        }
        final contents = textOf(file);
        if (contents == null) continue;
        for (final pattern in privilegedPatterns) {
          expect(
            contents.contains(pattern),
            isFalse,
            reason:
                '${normalized(file)} contains a privileged credential marker '
                '"$pattern"; privileged credentials must never ship with the '
                'client (NFR-029, ADR-009)',
          );
        }
      }
    }
  });

  test('the rules enforce both-consent activation without a server', () {
    // A regression guard on the security-critical invariant that replaces the
    // Cloud Function: activation must be authorized by BOTH members' consent
    // documents, which the rules read for themselves.
    final rules = File('firebase/firestore.rules').readAsStringSync();

    expect(
      rules.contains('bothConsentsGranted'),
      isTrue,
      reason: 'Pair activation must verify both consents (ADR-009)',
    );
    expect(
      rules.contains("request.resource.data.status == 'active'"),
      isTrue,
      reason: 'The activation transition must exist and be gated',
    );
    // Pairing codes may be redeemed but never enumerated.
    expect(
      rules.contains('match /pairingCodes/'),
      isTrue,
      reason: 'Pairing codes must be rule-governed, not server-issued',
    );
    // Notifications are per-user records written by the owner's own device.
    expect(
      rules.contains('match /notifications/'),
      isTrue,
      reason: 'Notifications must be per-user under Spark',
    );
  });
}
