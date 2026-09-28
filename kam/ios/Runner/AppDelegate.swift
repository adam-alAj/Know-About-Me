import CoreLocation
import Flutter
import UserNotifications
import Network
import UIKit

/// Foreground-only location bridge (Phase 10).
///
/// Uses only public Core Location APIs: when-in-use authorization, one-shot
/// `requestLocation()` reads and throttled `startUpdatingLocation()` updates.
/// Reduced ("approximate") accuracy is reported as-is and never upgraded.
/// No coordinates are logged.
private final class LocationBridge: NSObject, CLLocationManagerDelegate, FlutterStreamHandler {
  private let manager = CLLocationManager()
  private var eventSink: FlutterEventSink?
  private var pendingPermissionResult: FlutterResult?
  private var pendingLocationResult: FlutterResult?

  override init() {
    super.init()
    manager.delegate = self
    // Throttling: no continuous high-accuracy tracking while the app is open.
    manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    manager.distanceFilter = 100
  }

  private var authorizationStatus: CLAuthorizationStatus {
    if #available(iOS 14.0, *) { return manager.authorizationStatus }
    return CLLocationManager.authorizationStatus()
  }

  private var preciseAccuracy: Bool {
    if #available(iOS 14.0, *) { return manager.accuracyAuthorization == .fullAccuracy }
    return true
  }

  /// OS permission + service state. Never prompts.
  func statusMap() -> [String: Any] {
    let permission: String
    switch authorizationStatus {
    case .notDetermined: permission = "notDetermined"
    case .restricted: permission = "restricted"
    case .denied: permission = "denied"
    case .authorizedWhenInUse, .authorizedAlways: permission = "granted"
    @unknown default: permission = "unknown"
    }
    return [
      "supported": true,
      "permission": permission,
      "precise": preciseAccuracy,
      "serviceEnabled": CLLocationManager.locationServicesEnabled(),
    ]
  }

  /// Asks for when-in-use authorization once; refuses to re-ask after a
  /// denial or an OS-level restriction.
  func requestPermission(_ result: @escaping FlutterResult) {
    switch authorizationStatus {
    case .notDetermined:
      pendingPermissionResult = result
      manager.requestWhenInUseAuthorization()
    default:
      result(statusMap())
    }
  }

  /// One fix: a recent cached value if available, otherwise a single request.
  func requestCurrentLocation(_ result: @escaping FlutterResult) {
    guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
      result(["error": "denied"])
      return
    }
    guard CLLocationManager.locationServicesEnabled() else {
      result(["error": "disabled"])
      return
    }
    if let cached = manager.location, abs(cached.timestamp.timeIntervalSinceNow) <= 60 {
      result(locationMap(cached))
      return
    }
    if pendingLocationResult != nil {
      result(["error": "no_fix"])
      return
    }
    pendingLocationResult = result
    manager.requestLocation()
  }

  private func locationMap(_ location: CLLocation) -> [String: Any] {
    let formatter = ISO8601DateFormatter()
    return [
      "latitude": location.coordinate.latitude,
      "longitude": location.coordinate.longitude,
      "accuracyMeters": location.horizontalAccuracy >= 0 ? location.horizontalAccuracy : NSNull(),
      "observedAt": formatter.string(from: location.timestamp),
      "approximate": !preciseAccuracy,
    ]
  }

  // MARK: - CLLocationManagerDelegate

  func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
    guard let result = pendingPermissionResult else { return }
    pendingPermissionResult = nil
    result(statusMap())
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let location = locations.last else { return }
    if let result = pendingLocationResult {
      pendingLocationResult = nil
      result(locationMap(location))
      return
    }
    // Throttled updates are delivered by Core Location's own distance filter.
    eventSink?(locationMap(location))
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    guard let result = pendingLocationResult else { return }
    pendingLocationResult = nil
    if let clError = error as? CLError, clError.code == .locationUnknown {
      result(["error": "timeout"])
    } else {
      result(["error": "no_fix"])
    }
  }

  // MARK: - FlutterStreamHandler

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
      return FlutterError(code: "location_permission_missing", message: "Location permission is not granted.", details: nil)
    }
    guard CLLocationManager.locationServicesEnabled() else {
      return FlutterError(code: "location_service_disabled", message: "Location services are disabled.", details: nil)
    }
    manager.startUpdatingLocation()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    manager.stopUpdatingLocation()
    eventSink = nil
    return nil
  }
}

private final class BatteryEventHandler: NSObject, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?
  private var observerTokens: [NSObjectProtocol] = []

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    let device = UIDevice.current
    device.isBatteryMonitoringEnabled = true
    for name in [UIDevice.batteryLevelDidChangeNotification, UIDevice.batteryStateDidChangeNotification] {
      observerTokens.append(
        NotificationCenter.default.addObserver(forName: name, object: device, queue: .main) { [weak self] _ in
          self?.emitCurrentState()
        }
      )
    }
    emitCurrentState()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    observerTokens.forEach { NotificationCenter.default.removeObserver($0) }
    observerTokens.removeAll()
    eventSink = nil
    UIDevice.current.isBatteryMonitoringEnabled = false
    return nil
  }

  func emitCurrentState() {
    eventSink?(batteryReading())
  }
}

private func batteryReading() -> [String: Any] {
  let device = UIDevice.current
  device.isBatteryMonitoringEnabled = true
  let level = device.batteryLevel
  let percentage: Int? = level.isFinite && level >= 0 && level <= 1
    ? Int((level * 100).rounded())
    : nil
  let chargingState: String
  switch device.batteryState {
  case .charging:
    chargingState = "charging"
  case .full:
    chargingState = "full"
  case .unplugged:
    chargingState = "discharging"
  case .unknown:
    chargingState = "unknown"
  @unknown default:
    chargingState = "unknown"
  }
  return [
    "percentage": percentage.map { $0 as Any } ?? NSNull(),
    "chargingState": chargingState,
    "chargingSource": NSNull(),
    "chargingSourceSupported": false,
  ]
}

private final class NetworkEventHandler: NSObject, FlutterStreamHandler {
  private var monitor: NWPathMonitor?
  private var eventSink: FlutterEventSink?

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    let pathMonitor = NWPathMonitor()
    monitor = pathMonitor
    pathMonitor.pathUpdateHandler = { [weak self] path in
      DispatchQueue.main.async {
        self?.eventSink?(networkReading(path))
      }
    }
    pathMonitor.start(queue: DispatchQueue(label: "kam.network-monitor"))
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    monitor?.cancel()
    monitor = nil
    eventSink = nil
    return nil
  }
}

private func networkReading(_ path: NWPath) -> [String: String] {
  switch path.status {
  case .satisfied:
    let connectivityType: String
    if path.usesInterfaceType(.wifi) {
      connectivityType = "wifi"
    } else if path.usesInterfaceType(.cellular) {
      connectivityType = "mobile"
    } else if path.usesInterfaceType(.wiredEthernet) {
      connectivityType = "ethernet"
    } else {
      connectivityType = "unknown"
    }
    // NWPath reports whether a connection path is usable; it does not verify
    // general Internet or Firebase reachability.
    return [
      "connectivityType": connectivityType,
      "internetReachability": "unknown",
      "onlineStatus": "online",
    ]
  case .unsatisfied:
    return [
      "connectivityType": "none",
      "internetReachability": "unavailable",
      "onlineStatus": "offline",
    ]
  case .requiresConnection:
    return [
      "connectivityType": "unknown",
      "internetReachability": "unknown",
      "onlineStatus": "unknown",
    ]
  @unknown default:
    return [
      "connectivityType": "unknown",
      "internetReachability": "unknown",
      "onlineStatus": "unknown",
    ]
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, UNUserNotificationCenterDelegate {
  /// Retained so Core Location delegate callbacks keep arriving.
  private var locationBridge: LocationBridge?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let notificationChannel = FlutterMethodChannel(
      name: "kam/local_notifications",
      binaryMessenger: engineBridge.pluginRegistry.registrar(forPlugin: "KamLocalNotifications")!.messenger()
    )
    notificationChannel.setMethodCallHandler { call, result in
      let center = UNUserNotificationCenter.current()
      switch call.method {
      case "permissionState":
        center.getNotificationSettings { settings in
          let state: String
          switch settings.authorizationStatus {
          case .authorized, .provisional, .ephemeral: state = "granted"
          case .notDetermined: state = "notDetermined"
          default: state = "denied"
          }
          DispatchQueue.main.async { result(state) }
        }
      case "requestPermission":
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, error in
          DispatchQueue.main.async {
            if let error = error { result(FlutterError(code: "permission", message: "Notification permission could not be requested.", details: nil)); return }
            center.getNotificationSettings { settings in
              let allowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
              DispatchQueue.main.async { result(allowed ? "granted" : "denied") }
            }
          }
        }
      case "show":
        guard let args = call.arguments as? [String: Any],
              let id = args["id"] as? String,
              let title = args["title"] as? String,
              let body = args["body"] as? String else {
          result(FlutterError(code: "invalid_request", message: "Notification content is incomplete.", details: nil)); return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let ruleId = args["payload"] as? String { content.userInfo = ["ruleId": ruleId] }
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil)) { error in
          DispatchQueue.main.async { if error != nil { result(FlutterError(code: "delivery", message: "The notification could not be shown.", details: nil)) } else { result(nil) } }
        }
      case "cancelAll":
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
        result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
    UNUserNotificationCenter.current().delegate = self

    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "KamBatteryChannel")!
    let methodChannel = FlutterMethodChannel(
      name: "kam/device_battery",
      binaryMessenger: registrar.messenger()
    )
    methodChannel.setMethodCallHandler { call, result in
      guard call.method == "getCurrentBatteryState" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(batteryReading())
      // A one-shot read should not leave battery monitoring enabled. The
      // event handler enables it for the duration of an active subscription.
      UIDevice.current.isBatteryMonitoringEnabled = false
    }

    let eventChannel = FlutterEventChannel(
      name: "kam/device_battery/events",
      binaryMessenger: registrar.messenger()
    )
    eventChannel.setStreamHandler(BatteryEventHandler())

    let networkMethodChannel = FlutterMethodChannel(
      name: "kam/device_network",
      binaryMessenger: registrar.messenger()
    )
    networkMethodChannel.setMethodCallHandler { call, result in
      guard call.method == "getCurrentNetworkState" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let monitor = NWPathMonitor()
      monitor.pathUpdateHandler = { path in
        DispatchQueue.main.async {
          result(networkReading(path))
          monitor.cancel()
        }
      }
      monitor.start(queue: DispatchQueue(label: "kam.network-read"))
    }

    let networkEventChannel = FlutterEventChannel(
      name: "kam/device_network/events",
      binaryMessenger: registrar.messenger()
    )
    networkEventChannel.setStreamHandler(NetworkEventHandler())

    // Phase 10: location. Foreground only, when-in-use authorization, no
    // background modes and no private APIs.
    let bridge = LocationBridge()
    locationBridge = bridge

    let locationMethodChannel = FlutterMethodChannel(
      name: "kam/device_location",
      binaryMessenger: registrar.messenger()
    )
    locationMethodChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "getLocationStatus":
        result(bridge.statusMap())
      case "requestLocationPermission":
        bridge.requestPermission(result)
      case "getCurrentLocation":
        bridge.requestCurrentLocation(result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let locationEventChannel = FlutterEventChannel(
      name: "kam/device_location/events",
      binaryMessenger: registrar.messenger()
    )
    locationEventChannel.setStreamHandler(bridge)
  }
}

extension AppDelegate {
  func userNotificationCenter(_ center: UNUserNotificationCenter,
                              willPresent notification: UNNotification,
                              withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    if #available(iOS 14.0, *) { completionHandler([.banner, .list, .sound]) }
    else { completionHandler([.alert, .sound]) }
  }
}
