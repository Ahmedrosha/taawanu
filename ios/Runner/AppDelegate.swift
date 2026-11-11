import Flutter
import UIKit
import WidgetKit

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

    // ويدجتس الشاشة الرئيسية: التطبيق بيبعت البيانات (JSON)، وبنحفظها في App Group ونحدّث الويدجتس.
    let widgets = FlutterMethodChannel(name: "taawanu/widgets", binaryMessenger: engineBridge.applicationRegistrar.messenger())
    widgets.setMethodCallHandler { call, result in
      guard call.method == "update" else {
        result(FlutterMethodNotImplemented)
        return
      }
      if let data = call.arguments as? [String: String], let store = UserDefaults(suiteName: "group.com.taawanu.taawanu") {
        for (key, value) in data {
          store.set(value, forKey: key)
        }
        WidgetCenter.shared.reloadAllTimelines()
      }
      result(nil)
    }
  }
}
