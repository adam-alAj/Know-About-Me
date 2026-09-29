import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kam/core/connectivity/connection_status.dart';
import 'package:kam/core/ui/widgets/connection_indicator.dart';
import 'package:kam/features/device_state/presentation/widgets/connection_status_banner.dart';

/// Phase 20 §9, §25, §26: the connection is stated in plain, non-technical
/// language, only about *this* device, and the UI stays silent when there is
/// nothing true to say.
void main() {
  Future<void> pumpIndicator(
    WidgetTester tester,
    ConnectionStatus status, {
    bool showWhenConnected = false,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: ConnectionIndicator(
            status: status,
            showWhenConnected: showWhenConnected,
          ),
        ),
      ),
    ),
  );

  testWidgets('unknown says nothing at all', (tester) async {
    await pumpIndicator(tester, ConnectionStatus.unknown);
    expect(find.byType(Text), findsNothing);
    expect(ConnectionIndicator.labelFor(ConnectionStatus.unknown), isNull);
  });

  testWidgets('a nominal connection stays out of the way', (tester) async {
    const status = ConnectionStatus(
      connectivity: ConnectivityState.online,
      synchronization: SynchronizationState.idle,
    );
    await pumpIndicator(tester, status);
    expect(find.text(ConnectionIndicator.connectedLabel), findsNothing);

    await pumpIndicator(tester, status, showWhenConnected: true);
    expect(find.text(ConnectionIndicator.connectedLabel), findsOneWidget);
  });

  testWidgets('offline is about this connection, never about the partner', (
    tester,
  ) async {
    const status = ConnectionStatus(
      connectivity: ConnectivityState.offline,
      synchronization: SynchronizationState.pending,
    );
    await pumpIndicator(tester, status);

    expect(find.text(ConnectionIndicator.offlineLabel), findsOneWidget);
    // No wording anywhere may imply the other person's device is switched off.
    final labels = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data ?? '')
        .join(' ')
        .toLowerCase();
    for (final discouraged in <String>[
      'turned off',
      'powered off',
      'unavailable',
    ]) {
      expect(labels.contains(discouraged), isFalse);
    }
  });

  testWidgets('a permanent refusal asks for permission', (tester) async {
    const status = ConnectionStatus(
      connectivity: ConnectivityState.online,
      synchronization: SynchronizationState.blocked,
    );
    await pumpIndicator(tester, status);
    expect(find.text(ConnectionIndicator.blockedLabel), findsOneWidget);
  });

  testWidgets('an in-flight run is reported as syncing', (tester) async {
    const status = ConnectionStatus(
      connectivity: ConnectivityState.online,
      synchronization: SynchronizationState.syncing,
    );
    await pumpIndicator(tester, status);
    expect(find.text(ConnectionIndicator.syncingLabel), findsOneWidget);
  });

  testWidgets('a reconnection is reported as catching up', (tester) async {
    const status = ConnectionStatus(
      connectivity: ConnectivityState.online,
      synchronization: SynchronizationState.idle,
      recovery: RecoveryState.inProgress,
    );
    await pumpIndicator(tester, status);
    expect(find.text(ConnectionIndicator.catchingUpLabel), findsOneWidget);
  });

  testWidgets('the global banner is silent before anything is known', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(bottomNavigationBar: ConnectionStatusBanner()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // No Firebase means no evidence, and no evidence must never be rendered as
    // "offline" (Phase 20 §9).
    expect(find.byType(ConnectionIndicator), findsNothing);
  });
}
