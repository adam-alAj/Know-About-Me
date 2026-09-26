import 'package:flutter_riverpod/flutter_riverpod.dart';
// `Override` is exposed from the misc library in Riverpod 3.x.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:kam/app/app.dart';
import 'package:kam/app/providers.dart';
import 'package:kam/app/router/app_router.dart';
import 'package:kam/core/config/app_config.dart';
import 'package:kam/core/config/app_environment.dart';
import 'package:kam/core/time/clock.dart';

/// Deterministic configuration used by every widget test.
const AppConfig testConfig = AppConfig(
  environment: AppEnvironment.development,
  enableVerboseLogging: true,
);

/// An override that pins the clock to [now], making freshness deterministic.
Override fixedClock(DateTime now) =>
    clockProvider.overrideWithValue(FixedClock(now));

/// Pumps the real root widget with test overrides and a controllable router.
///
/// Returns the router so tests can drive or inspect navigation.
Future<GoRouter> pumpTestApp(
  WidgetTester tester, {
  List<Override> overrides = const <Override>[],
  String initialLocation = '/',
}) async {
  final router = createAppRouter(initialLocation: initialLocation);

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(testConfig),
        ...overrides,
      ],
      child: KamApp(config: testConfig, router: router),
    ),
  );
  await tester.pumpAndSettle();

  return router;
}
