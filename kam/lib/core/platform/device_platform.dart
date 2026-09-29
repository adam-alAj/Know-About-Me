/// The mobile platform a device runs, as reported by the device itself.
///
/// Lives in `core/` (not in a feature) because both the platform abstraction and
/// the device-state domain model need it, and `core/` must never depend on a
/// feature. Moved here in Phase 2 from `features/device_state`; the model is
/// unchanged. See `docs/architecture/ARCHITECTURE.md` §2.
///
/// The application is cross-platform (SRS 1.1), so platform identity is needed
/// to decide which capabilities are even worth asking about (NFR-008, NFR-019).
enum DevicePlatform {
  android,

  /// A platform the application does not recognise. Capabilities for such a
  /// device (including an iOS target) must be reported as unsupported rather
  /// than assumed. Android is the only deployment target for this application.
  unknown,
}
