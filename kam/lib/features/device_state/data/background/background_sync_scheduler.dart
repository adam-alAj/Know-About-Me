import 'dart:ui' show DartPluginRegistrant;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import '../../../../core/firebase/firebase_options.dart';
import '../../../../core/logging/app_logger.dart';
import '../services/app_device_identity.dart';
import '../services/shared_preferences_device_identity_store.dart';
import '../services/shared_preferences_sync_version_store.dart';
import 'background_device_state_sync.dart';
import 'background_partner_sync.dart';

const _partnerSyncTask = 'kam.partnerStateCatchUp';
const _partnerSyncUniqueName = 'com.example.kam.partner-state-catch-up';

/// Runs source-device sampling/publication, then refreshes authorized partner
/// documents into Firestore's local cache. Android WorkManager is deferred and
/// opportunistic; event-driven source updates are still used while the app
/// process remains resident.
@pragma('vm:entry-point')
void backgroundSyncCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != _partnerSyncTask && task != Workmanager.iOSBackgroundTask) {
      return true;
    }

    const logger = DeveloperAppLogger();
    try {
      logger.info('BACKGROUND_PARTNER_CATCHUP_STARTED');
      DartPluginRegistrant.ensureInitialized();
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }

      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) {
        logger.info(
          'BACKGROUND_PARTNER_CATCHUP_SKIPPED',
          context: {'reason': 'no_authenticated_user'},
        );
        return true;
      }

      if (defaultTargetPlatform == TargetPlatform.android) {
        final versionStore = SharedPreferencesSyncVersionStore();
        await BackgroundDeviceStateSync(
          FirebaseFirestore.instance,
          deviceIdentity: AppDeviceIdentity(
            SharedPreferencesDeviceIdentityStore(),
          ),
          readVersion: versionStore.read,
          writeVersion: versionStore.write,
          logger: logger,
        ).publishFor(userId);
      }

      await BackgroundPartnerSync(
        FirebaseFirestore.instance,
      ).refreshSharedStateFor(userId);
      logger.info('BACKGROUND_PARTNER_CATCHUP_SUCCEEDED');
      return true;
    } on FirebaseException catch (error) {
      // A permission-denied can mean consent/sharing changed while the job was
      // being scheduled. Retrying it cannot restore authorization.
      logger.warning(
        'BACKGROUND_PARTNER_CATCHUP_FAILED',
        context: {'errorCode': error.code},
      );
      if (error.code == 'permission-denied' ||
          error.code == 'unauthenticated') {
        return true;
      }
      return false;
    } catch (error, stackTrace) {
      logger.warning(
        'BACKGROUND_PARTNER_CATCHUP_FAILED',
        error: error,
        stackTrace: stackTrace,
        context: {'errorType': error.runtimeType.toString()},
      );
      return false;
    }
  });
}

abstract final class BackgroundSyncScheduler {
  static bool _initialized = false;

  static Future<void> initializeAndSchedule() async {
    if (_initialized) return;
    await Workmanager().initialize(backgroundSyncCallbackDispatcher);
    await Workmanager().registerPeriodicTask(
      _partnerSyncUniqueName,
      _partnerSyncTask,
      frequency: const Duration(minutes: 15),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      constraints: Constraints(networkType: NetworkType.connected),
    );
    _initialized = true;
  }
}
