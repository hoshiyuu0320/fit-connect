import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // ローカル通知（flutter_local_notifications）の表示とタップを受け取るため、
    // 通知センターの delegate をこの AppDelegate にする（FLN の README の iOS 設定）。
    // FlutterAppDelegate は willPresent / didReceive を addApplicationDelegate した
    // すべてのプラグイン（firebase_messaging と FLN）へ回し、どちらも自分の通知だけを扱う。
    // firebase_messaging は delegate が FlutterAppLifeCycleProvider（この AppDelegate）なら
    // 置き換えず、回ってくる呼び出しで受けるので、FCM の表示とタップは変わらない。
    // 通知のタップで起動したときに取りこぼさないよう、起動が終わる前のここで設定する
    // （プラグインの登録は didInitializeImplicitFlutterEngine だが、delegate は登録に依存しない）
    UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
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
