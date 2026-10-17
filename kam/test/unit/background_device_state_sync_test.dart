import 'package:flutter_test/flutter_test.dart';
import 'package:kam/features/device_state/data/background/background_device_state_sync.dart';
import 'package:kam/features/device_state/domain/models/activity_state.dart';
import 'package:kam/features/device_state/domain/models/battery_state.dart';
import 'package:kam/features/device_state/domain/models/network_state.dart';
import 'package:kam/features/device_state/domain/models/state_observation.dart';

void main() {
  final observedAt = DateTime.utc(2026, 10, 17, 3, 15);

  test('maps supported Android samples without inventing other metrics', () {
    final snapshot = BackgroundDeviceStateSync.snapshotFromSample(
      {
        'observedAtEpochMillis': observedAt.millisecondsSinceEpoch,
        'batteryPercentage': 76,
        'chargingState': 'charging',
        'chargingSource': 'usb',
        'connectivityType': 'wifi',
        'internetReachability': 'available',
        'networkStatus': 'online',
        'screenState': 'off',
      },
      ownerId: 'owner-1',
      deviceId: 'device-opaque-id',
      fallbackObservedAt: DateTime.utc(2026),
    );

    expect(snapshot.userId, 'owner-1');
    expect(snapshot.deviceId, 'device-opaque-id');
    expect(snapshot.collectedAt, observedAt);
    expect(snapshot.battery?.percentage.value, 76);
    expect(
      snapshot.battery?.chargingState.value,
      BatteryChargingState.charging,
    );
    expect(
      snapshot.battery?.chargingDuration.availability,
      CapabilityAvailability.unknown,
    );
    expect(snapshot.network?.connectivity.value, ConnectivityType.wifi);
    expect(snapshot.network?.status.value, NetworkOnlineStatus.online);
    expect(snapshot.activity?.screenState.value, DeviceScreenState.off);
    expect(snapshot.activity?.appLifecycle.value, AppLifecyclePhase.background);
    expect(snapshot.activity?.lastObservedActivityAt, isNull);
    expect(snapshot.location, isNull);
  });

  test('missing or unknown native values remain unknown', () {
    final snapshot = BackgroundDeviceStateSync.snapshotFromSample(
      const <String, Object?>{
        'chargingState': 'futureValue',
        'connectivityType': 'futureNetwork',
        'internetReachability': 'futureReachability',
        'networkStatus': 'unknown',
        'screenState': 'unknown',
      },
      ownerId: 'owner-1',
      deviceId: 'device-opaque-id',
      fallbackObservedAt: observedAt,
    );

    expect(snapshot.collectedAt, observedAt);
    expect(
      snapshot.battery?.percentage.availability,
      CapabilityAvailability.unknown,
    );
    expect(snapshot.battery?.chargingState.value, isNull);
    expect(snapshot.network?.status.value, isNull);
    expect(snapshot.activity?.screenState.value, isNull);
    expect(snapshot.location, isNull);
  });
}
