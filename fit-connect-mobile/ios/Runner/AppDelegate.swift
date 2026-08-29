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
  }

  // APNs 登録の成否を可視化するための診断ログ。
  // super 呼び出しで Flutter プラグイン（Firebase Messaging の
  // スウィズリング含む）への転送は維持される。
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    let token = deviceToken.map { String(format: "%02x", $0) }.joined()
    NSLog("[AppDelegate] APNs 登録成功: %@...", String(token.prefix(16)))
    super.application(
      application,
      didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    NSLog("[AppDelegate] APNs 登録失敗: %@", error.localizedDescription)
    NSLog("[AppDelegate] APNs 登録失敗詳細: %@", String(describing: error))
    super.application(
      application,
      didFailToRegisterForRemoteNotificationsWithError: error)
  }
}
