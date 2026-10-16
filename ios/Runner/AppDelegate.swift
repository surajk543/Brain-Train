import AppTrackingTransparency
import Flutter
import UIKit

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
