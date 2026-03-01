import Flutter
import UIKit
import WebKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let flutterViewController = window?.rootViewController as? FlutterViewController {
      let cookieChannel = FlutterMethodChannel(
        name: "river/webview_cookies",
        binaryMessenger: flutterViewController.binaryMessenger
      )
      cookieChannel.setMethodCallHandler { [weak self] call, result in
        guard let self else {
          result(false)
          return
        }
        switch call.method {
        case "getCookies":
          guard
            let args = call.arguments as? [String: Any],
            let urlString = args["url"] as? String
          else {
            result(nil)
            return
          }
          self.getCookies(urlString: urlString, result: result)
        case "setCookies":
          guard
            let args = call.arguments as? [String: Any],
            let urlString = args["url"] as? String,
            let cookieHeader = args["cookieHeader"] as? String
          else {
            result(false)
            return
          }
          self.setCookies(urlString: urlString, cookieHeader: cookieHeader, result: result)
        case "clearAllCookies":
          self.clearAllCookies(result: result)
        default:
          result(FlutterMethodNotImplemented)
        }
      }

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

  private func cookieStore() -> WKHTTPCookieStore {
    WKWebsiteDataStore.default().httpCookieStore
  }

  private func getCookies(urlString: String, result: @escaping FlutterResult) {
    guard
      let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
      let host = url.host?.lowercased()
    else {
      result(nil)
      return
    }
    cookieStore().getAllCookies { cookies in
      let matched = cookies.filter { cookie in
        let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if domain.isEmpty { return false }
        return host == domain || host.hasSuffix(".\(domain)")
      }
      let header = matched
        .map { "\($0.name)=\($0.value)" }
        .joined(separator: "; ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
      result(header.isEmpty ? nil : header)
    }
  }

  private func setCookies(urlString: String, cookieHeader: String, result: @escaping FlutterResult) {
    guard
      let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
      let host = url.host?.lowercased()
    else {
      result(false)
      return
    }
    let pairs = cookieHeader
      .split(separator: ";")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { $0.contains("=") }
    if pairs.isEmpty {
      result(false)
      return
    }
    let secure = (url.scheme?.lowercased() == "https")
    let group = DispatchGroup()
    var success = true
    for pair in pairs {
      let parts = pair.split(separator: "=", maxSplits: 1)
      guard parts.count == 2 else { continue }
      let name = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
      let value = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
      if name.isEmpty { continue }
      var properties: [HTTPCookiePropertyKey: Any] = [
        .name: name,
        .value: value,
        .domain: host,
        .path: "/",
      ]
      if secure {
        properties[.secure] = "TRUE"
      }
      guard let cookie = HTTPCookie(properties: properties) else {
        success = false
        continue
      }
      group.enter()
      cookieStore().setCookie(cookie) {
        group.leave()
      }
    }
    group.notify(queue: .main) {
      result(success)
    }
  }

  private func clearAllCookies(result: @escaping FlutterResult) {
    cookieStore().getAllCookies { cookies in
      if cookies.isEmpty {
        result(true)
        return
      }
      let group = DispatchGroup()
      for cookie in cookies {
        group.enter()
        self.cookieStore().delete(cookie) {
          group.leave()
        }
      }
      group.notify(queue: .main) {
        result(true)
      }
    }
  }
}
