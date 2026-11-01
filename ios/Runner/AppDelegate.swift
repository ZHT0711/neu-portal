import Flutter
import UIKit
import WebKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var sessionChannel: FlutterMethodChannel?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PortalSessionCookies") else { return }
    let channel = FlutterMethodChannel(name: "neu.portal/session_cookies", binaryMessenger: registrar.messenger())
    sessionChannel = channel
    channel.setMethodCallHandler { call, result in
      let store = WKWebsiteDataStore.default().httpCookieStore
      if call.method == "read" {
        store.getAllCookies { cookies in
          result(cookies.filter {
            let domain = $0.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return domain == "neu.edu.cn" || domain.hasSuffix(".neu.edu.cn")
          }.map { cookie -> [String: Any] in
            var record: [String: Any] = ["name": cookie.name, "value": cookie.value, "domain": cookie.domain,
             "path": cookie.path, "secure": cookie.isSecure, "httpOnly": cookie.isHTTPOnly,
             "hostOnly": !cookie.domain.hasPrefix("."),
             "expires": NSNull()]
            if let expires = cookie.expiresDate { record["expires"] = expires.timeIntervalSince1970 * 1000 }
            return record
          })
        }
      } else if call.method == "restore", let records = call.arguments as? [[String: Any]] {
        let group = DispatchGroup()
        for record in records {
          guard let name = record["name"] as? String, let value = record["value"] as? String,
                let domain = record["domain"] as? String, let path = record["path"] as? String,
                domain == "neu.edu.cn" || domain.hasSuffix(".neu.edu.cn") else { continue }
          let cookieDomain = record["hostOnly"] as? Bool == true || domain.hasPrefix(".") ? domain : "." + domain
          var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name, .value: value, .domain: cookieDomain, .path: path]
          if record["secure"] as? Bool == true { properties[.secure] = "TRUE" }
          if record["httpOnly"] as? Bool == true {
            properties[HTTPCookiePropertyKey(rawValue: "HttpOnly")] = "TRUE"
          }
          if let milliseconds = record["expires"] as? Double {
            let expires = Date(timeIntervalSince1970: milliseconds / 1000)
            guard expires > Date() else { continue }
            properties[.expires] = expires
          }
          if let cookie = HTTPCookie(properties: properties) {
            group.enter()
            store.setCookie(cookie) { group.leave() }
          }
        }
        group.notify(queue: .main) { result(nil) }
      } else { result(FlutterMethodNotImplemented) }
    }
  }
}
