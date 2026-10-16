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
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BrainTrainPlatform") {
      let channel = FlutterMethodChannel(name: "brain_train/platform", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        switch call.method {
        case "rewardedAdUnitId":
          result(Bundle.main.object(forInfoDictionaryKey: "BrainTrainRewardedAdUnitId") as? String)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }
}
