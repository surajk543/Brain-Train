import AppTrackingTransparency
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Keeps the iCloud change observer alive (cloud save, `brain_train/cloud`).
  private var cloudObserver: NSObjectProtocol?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Tells Dart this build's rewarded ad unit (Info.plist BrainTrainRewardedAdUnitId;
    // docs/ADS.md). Dart falls back to Google's test unit without an answer.
    // Opens the App Store page for the lobby's update card (docs/APP_UPDATES.md).
    // Asks App Tracking Transparency for 13+ players before ads start (docs/ADS.md).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BrainTrainPlatform") {
      let channel = FlutterMethodChannel(name: "brain_train/platform", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        switch call.method {
        case "rewardedAdUnitId":
          result(Bundle.main.object(forInfoDictionaryKey: "BrainTrainRewardedAdUnitId") as? String)
        case "openUrl":
          guard let args = call.arguments as? [String: Any],
                let text = args["url"] as? String,
                let url = URL(string: text),
                url.scheme == "https" || url.scheme == "itms-apps" else {
            result(false)
            return
          }
          UIApplication.shared.open(url, options: [:]) { opened in result(opened) }
        case "requestTrackingAuthorization":
          // iOS shows the prompt once per install; later calls get the answer.
          guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else {
            result(AppDelegate.trackingName(ATTrackingManager.trackingAuthorizationStatus))
            return
          }
          ATTrackingManager.requestTrackingAuthorization { status in
            DispatchQueue.main.async { result(AppDelegate.trackingName(status)) }
          }
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
    // Cloud save: the progress in the player's iCloud key-value storage, so it
    // survives a reinstall (lib/platform/icloud_store.dart). Tells Dart when
    // the values change from outside (the first sync after an install,
    // another device).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BrainTrainCloud") {
      let cloud = FlutterMethodChannel(name: "brain_train/cloud", binaryMessenger: registrar.messenger())
      let store = NSUbiquitousKeyValueStore.default
      cloud.setMethodCallHandler { call, result in
        let args = call.arguments as? [String: Any]
        switch call.method {
        case "read":
          guard let key = args?["key"] as? String else {
            result(nil)
            return
          }
          result(store.string(forKey: key))
        case "write":
          guard let key = args?["key"] as? String, let value = args?["value"] as? String else {
            result(false)
            return
          }
          store.set(value, forKey: key)
          result(store.synchronize())
        default:
          result(FlutterMethodNotImplemented)
        }
      }
      cloudObserver = NotificationCenter.default.addObserver(
        forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: store, queue: .main
      ) { _ in
        cloud.invokeMethod("changed", arguments: nil)
      }
      store.synchronize()
    }
  }

  private static func trackingName(_ status: ATTrackingManager.AuthorizationStatus) -> String {
    switch status {
    case .authorized: return "authorized"
    case .denied: return "denied"
    case .restricted: return "restricted"
    case .notDetermined: return "notDetermined"
    @unknown default: return "unknown"
    }
  }
}
