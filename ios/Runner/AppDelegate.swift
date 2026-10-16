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
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }
}
