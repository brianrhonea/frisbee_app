import Flutter
import UIKit
import UserNotifications

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
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "Stall10Notifications") {
      let channel = FlutterMethodChannel(
        name: "stall10/notifications", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        guard call.method == "clearDelivered", let thread = call.arguments as? String else {
          result(FlutterMethodNotImplemented)
          return
        }
        clearDelivered(thread: thread)
        result(nil)
      }
    }
  }
}

/// Removes delivered notifications in [thread] (the push's apns threadId,
/// set from the notice's collapse id in functions/src/notifications).
func clearDelivered(thread: String) {
  let center = UNUserNotificationCenter.current()
  center.getDeliveredNotifications { delivered in
    let ids = delivered
      .filter { $0.request.content.threadIdentifier == thread }
      .map { $0.request.identifier }
    if !ids.isEmpty { center.removeDeliveredNotifications(withIdentifiers: ids) }
  }
}
