import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kam/core/domain/device_metric.dart';
import 'package:kam/features/device_state/data/providers/platform_device_state_provider.dart';
import 'package:kam/features/device_state/domain/models/device_state_snapshot.dart';
import 'package:kam/features/device_state/domain/repositories/device_state_repository.dart';
import 'package:kam/features/device_state/presentation/providers/device_monitoring_lifecycle.dart';

/// Phase 20 §20, §21: a resumed application cannot assume a background listener
/// survived, and it must not end up with two listeners either. Resuming is a
/// restart of one listener, never an addition.
void main() {
  testWidgets('resume restarts one monitoring listener, never a second', (
    tester,
  ) async {
    final repository = _CountingRepository();
    final controller = DeviceMonitoringController(repository);
    var resumes = 0;

    await tester.pumpWidget(
      DeviceMonitoringLifecycle(
        controller: controller,
        onResume: () => resumes++,
        child: const SizedBox.shrink(),
      ),
    );
    expect(repository.subscriptions, 1);

    // The registered observer is driven directly: the transitions this widget
    // acts on are its own, and the platform's lifecycle channel is not what
    // Phase 20 needs to exercise here.
    final observer =
        tester.state(find.byType(DeviceMonitoringLifecycle))
            as WidgetsBindingObserver;

    // Backgrounding releases the platform subscription promptly.
    observer.didChangeAppLifecycleState(AppLifecycleState.paused);
    // `stopMonitoring` releases the subscription and only then clears its
    // handle, so the event loop is given a turn before the resume is observed.
    await tester.pumpAndSettle();
    expect(repository.cancellations, 1);
    expect(resumes, 0);

    observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(resumes, 1);
    expect(repository.subscriptions, 2);
    // Still only the one active subscription; the released one was cancelled.
    expect(repository.cancellations, 1);

    // A second resume while already foregrounded must not stack listeners.
    observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(resumes, 2);
    expect(repository.subscriptions, 2);
    expect(repository.cancellations, 1);
  });
}

class _CountingRepository implements DeviceStateRepository {
  int subscriptions = 0;
  int cancellations = 0;

  static final DeviceStateSnapshot _snapshot = DeviceStateSnapshot(
    deviceId: 'device-1',
    userId: 'user-a',
    collectedAt: DateTime.utc(2026, 9, 28),
    capabilities: const <DeviceMetric, StateObservation<Object?>>{},
  );

  @override
  Map<DeviceMetric, DeviceCapabilityStatus> get capabilityStatus =>
      const <DeviceMetric, DeviceCapabilityStatus>{};

  @override
  Future<DeviceStateSnapshot> getCurrentLocalState() async => _snapshot;

  @override
  Future<DeviceStateSnapshot> refresh() async => _snapshot;

  @override
  Stream<DeviceStateSnapshot> watchLocalState() =>
      StreamController<DeviceStateSnapshot>(
        onListen: () => subscriptions++,
        onCancel: () => cancellations++,
      ).stream;
}
