import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'firebase_bootstrap.dart';

/// Raw Firebase handles, exposed so that feature code can be *composed* with
/// Firebase without importing the SDK itself.
///
/// `test/architecture/domain_purity_test.dart` allows Firebase imports **only**
/// in `lib/core/firebase/` and in `lib/features/*/data/` (ADR-007). The
/// dependency-injection wiring in `features/auth/presentation/providers/`
/// therefore reads these providers: passing `firebaseAuthProvider` into
/// `FirebaseAuthRepository` needs no SDK import at the call site, so the
/// boundary stays machine-checked rather than merely intended.
///
/// Reading these providers before Firebase initialized would throw, so ask
/// [firebaseAvailableProvider] (or `FirebaseBootstrap.isInitialized`) first.
/// `authRepositoryProvider` does exactly that.
final firebaseAvailableProvider = Provider<bool>(
  (ref) => FirebaseBootstrap.isInitialized,
);

/// The Firebase Authentication handle.
final firebaseAuthProvider = Provider<FirebaseAuth>(
  (ref) => FirebaseAuth.instance,
);

/// The Cloud Firestore handle.
final firebaseFirestoreProvider = Provider<FirebaseFirestore>(
  (ref) => FirebaseFirestore.instance,
);
