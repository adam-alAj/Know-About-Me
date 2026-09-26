/// Persistent storage boundary for an opaque app-generated device identifier.
abstract interface class DeviceIdentityStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> remove();
}
