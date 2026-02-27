import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let flutterViewController = window?.rootViewController as? FlutterViewController {
      let iconChannel = FlutterMethodChannel(
        name: "river/app_icon",
        binaryMessenger: flutterViewController.binaryMessenger
      )
      iconChannel.setMethodCallHandler { [weak self] call, result in
        guard call.method == "switchIcon" else {
          result(FlutterMethodNotImplemented)
          return
        }
        guard
          let args = call.arguments as? [String: Any],
          let preset = args["preset"] as? String
        else {
          result(false)
          return
        }
        self?.switchAppIcon(preset: preset, result: result)
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func switchAppIcon(preset: String, result: @escaping FlutterResult) {
    guard UIApplication.shared.supportsAlternateIcons else {
      result(false)
      return
    }

    let iconName: String?
    switch preset {
    case "origin":
      iconName = nil
    case "quality":
      iconName = "AppIconQuality"
    case "pixel":
      iconName = "AppIconPixel"
    case "cloud":
      iconName = "AppIconCloud"
    case "neon":
      iconName = "AppIconNeon"
    case "vaporwave":
      iconName = "AppIconVaporwave"
    case "china":
      iconName = "AppIconChina"
    case "chengdu":
      iconName = "AppIconChengdu"
    case "animation":
      iconName = "AppIconAnimation"
    case "sweet":
      iconName = "AppIconSweet"
    default:
      result(false)
      return
    }

    UIApplication.shared.setAlternateIconName(iconName) { error in
      result(error == nil)
    }
  }
}
