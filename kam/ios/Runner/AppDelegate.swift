import Flutter
import UIKit

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

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

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
  }
}
