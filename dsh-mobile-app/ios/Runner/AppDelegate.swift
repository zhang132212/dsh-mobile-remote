import Flutter
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 冷启动时系统可能在 Flutter 引擎就绪前就抛出「用 DSH Remote 打开文档」的
    // URL/场景回调，先确保原生桥单例存在，文档字节先暂存、等 Dart 侧就绪再投递。
    _ = DshNativeBridge.shared
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Flutter 3.47（UIScene 生命周期）下注册插件与自定义通道的入口：
  /// 隐式引擎创建完成后通过 engineBridge 拿到 pluginRegistry / applicationRegistrar。
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "DshNativeBridge") {
      DshNativeBridge.shared.attach(registrar: registrar)
    }
  }

  /// 外部文档/URL 打开（非 Scene 路径的兜底；带 Scene 的常规路径见 SceneDelegate）。
  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any]
  ) -> Bool {
    let handledByUs = DshNativeBridge.shared.handleIncomingURL(url)
    let handledByFlutter = super.application(app, open: url, options: options)
    return handledByUs || handledByFlutter
  }
}

/// 原生桥：dsh/files、dsh/update 两个 MethodChannel，以及外部文档打开（pendingDoc）机制。
///
/// 语义与 Android 侧 MainActivity.kt 对齐：
/// - dsh/files: saveToDownloads / pickFile / getIncomingFile / clearIncomingFile，
///   并主动向 Dart 投递 openDocument 事件（冷启动靠 Dart 侧 getIncomingFile 兜底）。
/// - dsh/update: installApk —— iOS 不允许应用内自更新，恒返回 false。
/// - dsh/floating: iOS 无系统级悬浮球，刻意不实现该通道（Dart 侧已降级）。
final class DshNativeBridge: NSObject, UIDocumentPickerDelegate {
  static let shared = DshNativeBridge()

  private static let filesChannelName = "dsh/files"
  private static let updateChannelName = "dsh/update"
  private static let savedFolderName = "DSH-Remote"

  private var filesChannel: FlutterMethodChannel?
  private var updateChannel: FlutterMethodChannel?
  private weak var viewController: UIViewController?

  /// 外部 App「用 DSH Remote 打开 / 分享到 DSH Remote」进来的文档。
  /// 引擎未就绪、或 Dart 侧 handler 尚未注册时先攥在手里，等就绪后投递；
  /// Dart 首帧后也会主动 getIncomingFile 拉一次（只读不清，清空权在 clearIncomingFile）。
  private var pendingDoc: [String: Any]?
  /// 去重：投递成功置 true，Dart 侧 clearIncomingFile 后复位；避免同一文档弹两次。
  private var docDelivered = false
  /// 系统文件选择器的回调（同一时刻只允许一个选择器）。
  private var pendingPickResult: FlutterResult?

  // MARK: - 注册

  func attach(registrar: FlutterPluginRegistrar) {
    viewController = registrar.viewController
    let messenger = registrar.messenger()

    let files = FlutterMethodChannel(name: Self.filesChannelName, binaryMessenger: messenger)
    files.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterMethodNotImplemented)
        return
      }
      self.handleFiles(call, result: result)
    }
    filesChannel = files

    let update = FlutterMethodChannel(name: Self.updateChannelName, binaryMessenger: messenger)
    update.setMethodCallHandler { call, result in
      // iOS 无应用内自更新：安装 APK 的功能恒不可用，安全返回 false（Dart 侧会提示降级）。
      if call.method == "installApk" {
        result(false)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    updateChannel = update

    // 首帧前后可能都有文档到达：通道就绪后把已暂存的文档补投一次。
    deliverPendingDoc()
  }

  // MARK: - dsh/files

  private func handleFiles(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "saveToDownloads":
      saveToDownloads(call, result: result)
    case "pickFile":
      pickFile(result: result)
    case "getIncomingFile":
      // 只读不消费：清空由 clearIncomingFile 负责，避免「投递失败 + 已置空」导致文档丢失。
      result(pendingDoc)
    case "clearIncomingFile":
      pendingDoc = nil
      docDelivered = false
      result(true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// 保存到 App 文稿目录（Documents/DSH-Remote，开启 UIFileSharingEnabled 后可在「文件」App 看到）。
  ///
  /// 返回值语义与 Android 侧对齐，但改为**人类可读文案**（不暴露沙盒绝对路径，
  /// 因为 Dart 侧会把它直接拼进 toast）。例："App 文稿/DSH-Remote/报告.docx"。
  private func saveToDownloads(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any] else {
      result(FlutterError(code: "bad-args", message: "missing arguments", details: nil))
      return
    }
    let name = Self.sanitizedFileName((args["name"] as? String) ?? "file")
    guard let typed = args["bytes"] as? FlutterStandardTypedData else {
      result(FlutterError(code: "bad-args", message: "missing bytes", details: nil))
      return
    }
    do {
      let dir = try documentsDirectory().appendingPathComponent(Self.savedFolderName, isDirectory: true)
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      let fileURL = dir.appendingPathComponent(name)
      try typed.data.write(to: fileURL, options: .atomic)
      // 可选：Dart 侧传 share=true 时弹系统分享面板（默认不弹，文件在「文件」App 可见）。
      if (args["share"] as? Bool) == true {
        presentShareSheet(for: fileURL)
      }
      result("App 文稿/\(Self.savedFolderName)/\(name)")
    } catch {
      result(FlutterError(code: "save-failed", message: error.localizedDescription, details: nil))
    }
  }

  /// 系统文件选择器（UIDocumentPickerViewController，导入副本），回传 {name, bytes}；
  /// 用户取消返回 null（不抛异常，Dart 侧按「取消」静默处理）。
  private func pickFile(result: @escaping FlutterResult) {
    guard pendingPickResult == nil else {
      result(FlutterError(code: "busy", message: "already picking", details: nil))
      return
    }
    guard let presenter = presentingViewController() else {
      result(FlutterError(code: "no-view", message: "no view controller to present picker", details: nil))
      return
    }
    pendingPickResult = result
    let picker = UIDocumentPickerViewController(
      forOpeningContentTypes: [.data, .item, .text, .image, .movie],
      asCopy: true
    )
    picker.delegate = self
    picker.allowsMultipleSelection = false
    presenter.present(picker, animated: true)
  }

  // MARK: - UIDocumentPickerDelegate

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let completion = pendingPickResult else { return }
    pendingPickResult = nil
    guard let url = urls.first else {
      completion(nil)
      return
    }
    do {
      let data = try readData(from: url)
      guard !data.isEmpty else {
        completion(FlutterError(code: "read-failed", message: "empty file", details: nil))
        return
      }
      let name = url.lastPathComponent.isEmpty ? "file" : url.lastPathComponent
      let payload: [String: Any] = [
        "name": name,
        "bytes": FlutterStandardTypedData(bytes: data),
      ]
      completion(payload)
    } catch {
      completion(FlutterError(code: "read-failed", message: error.localizedDescription, details: nil))
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    let completion = pendingPickResult
    pendingPickResult = nil
    completion?(nil)
  }

  // MARK: - 外部文档打开（file:// / security-scoped URL）

  /// 处理系统投递进来的外部文档 URL；返回是否已识别为文档。
  @discardableResult
  func handleIncomingURL(_ url: URL) -> Bool {
    guard url.isFileURL else { return false }
    let name = url.lastPathComponent.isEmpty ? "document" : url.lastPathComponent
    do {
      let data = try readData(from: url)
      var payload: [String: Any] = ["name": name]
      if data.isEmpty {
        payload["error"] = "empty"
      } else {
        payload["bytes"] = FlutterStandardTypedData(bytes: data)
      }
      pendingDoc = payload
    } catch {
      // 读失败也要投给 Dart：用户点了「用 DSH Remote 打开」却毫无反应会以为 App 坏了。
      pendingDoc = ["name": name, "error": error.localizedDescription]
    }
    docDelivered = false
    deliverPendingDoc()
    return true
  }

  /// 把暂存文档投给 Dart（引擎/通道未就绪时 no-op，等 attach 后再补投）。
  private func deliverPendingDoc() {
    guard let doc = pendingDoc, let channel = filesChannel, !docDelivered else { return }
    docDelivered = true
    channel.invokeMethod("openDocument", arguments: doc)
  }

  // MARK: - Helpers

  /// 读取外部文档字节：沙盒内文件直接读；iCloud/其他 App 的 security-scoped URL 先取访问权限。
  private func readData(from url: URL) throws -> Data {
    let scoped = url.startAccessingSecurityScopedResource()
    defer {
      if scoped { url.stopAccessingSecurityScopedResource() }
    }
    return try Data(contentsOf: url)
  }

  private func documentsDirectory() throws -> URL {
    guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
      throw NSError(domain: "DshNativeBridge", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "documents directory unavailable"])
    }
    return url
  }

  /// 去掉路径分隔符，避免外部传入的 name 越级写到别的目录。
  private static func sanitizedFileName(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    var name = trimmed.replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "\\", with: "_")
    if name.isEmpty || name == "." || name == ".." {
      name = "file"
    }
    return name
  }

  private func presentingViewController() -> UIViewController? {
    if let vc = viewController {
      return topMost(from: vc)
    }
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.first?.windows.first
    return topMost(from: window?.rootViewController)
  }

  private func topMost(from controller: UIViewController?) -> UIViewController? {
    var current = controller
    while let presented = current?.presentedViewController {
      current = presented
    }
    if let nav = current as? UINavigationController {
      return topMost(from: nav.visibleViewController)
    }
    if let tab = current as? UITabBarController {
      return topMost(from: tab.selectedViewController)
    }
    return current
  }

  private func presentShareSheet(for url: URL) {
    guard let presenter = presentingViewController() else { return }
    let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
    if let popover = activity.popoverPresentationController {
      popover.sourceView = presenter.view
      popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
    }
    presenter.present(activity, animated: true)
  }
}
