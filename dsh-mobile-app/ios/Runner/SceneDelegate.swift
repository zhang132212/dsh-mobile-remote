import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  /// 冷启动：App 因「用 DSH Remote 打开文档 / 分享到 DSH Remote」被拉起时，
  /// 文档 URL 在 scene 连接参数里（这种场景系统不会走 application(_:open:options:)）。
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    for context in connectionOptions.urlContexts {
      DshNativeBridge.shared.handleIncomingURL(context.url)
    }
  }

  /// 热启动：App 已在运行时再打开/分享一个文档（files App 用本 App 打开、分享面板「拷贝到」等）。
  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    super.scene(scene, openURLContexts: URLContexts)
    for context in URLContexts {
      DshNativeBridge.shared.handleIncomingURL(context.url)
    }
  }
}
