import 'app/bootstrap.dart';

/// Application entry point.
///
/// All startup work (configuration, logging, service preparation, dependency
/// overrides) lives in `AppBootstrap` so `main` stays a one-liner and the
/// sequence is testable. See `lib/app/bootstrap.dart`.
Future<void> main() => AppBootstrap.run();
