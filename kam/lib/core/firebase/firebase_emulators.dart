import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../config/app_config.dart';
import '../logging/app_logger.dart';

/// Default emulator ports, matching `firebase.json` in this repository.
abstract final class FirebaseEmulatorPorts {
  static const int firestore = 8080;
  static const int auth = 9099;
}

// NOTE: there is no `messaging` port. The Firebase Emulator Suite has no Cloud
// Messaging emulator, and messaging is not currently wired into the app.

/// Points the Firebase SDKs at the local Emulator Suite.
///
/// Local development must never write to production data (SRS constraint 6 in
/// the Phase 3 brief). Guarded so a failure here cannot prevent startup.
abstract final class FirebaseEmulators {
  /// Connects Firestore and Auth to the emulators.
  ///
  /// Returns `true` when the connection was established.
  static bool connect(AppConfig config, {required AppLogger logger}) {
    if (!config.useFirebaseEmulators) return false;

    final host = config.firebaseEmulatorHost;
    try {
      FirebaseFirestore.instance.useFirestoreEmulator(
        host,
        FirebaseEmulatorPorts.firestore,
      );
      FirebaseAuth.instance.useAuthEmulator(host, FirebaseEmulatorPorts.auth);

      logger.info(
        'Connected to Firebase Emulator Suite',
        context: {'host': host},
      );
      return true;
    } catch (error, stackTrace) {
      // Never log credentials; the host and the error type are enough.
      logger.error(
        'Failed to connect to the Firebase Emulator Suite',
        error: error,
        stackTrace: stackTrace,
        context: {'host': host},
      );
      return false;
    }
  }
}
