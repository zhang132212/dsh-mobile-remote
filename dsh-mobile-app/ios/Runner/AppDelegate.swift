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
  /// 外部文档 / picker 选择的文件大小上限。与 Dart 侧 lib/docs/loader.dart 的
  /// kMaxDocBytes = 24 * 1024 * 1024 对齐：超过上限不读内容，直接回报 too-large，
  /// 避免 iCloud 未下载的大文件把主线程/内存拖爆。
  private static let maxDocBytes = 24 * 1024 * 1024
  /// 文档投递成功后暂存字节的释放宽限：invokeMethod 不保证 Dart 已注册 handler，
  /// Dart 首帧还会 getIncomingFile 兜底，所以不能立刻清；宽限到期后释放避免常驻内存。
  private static let pendingDocReleaseDelay: TimeInterval = 60

  private var filesChannel: FlutterMethodChannel?
  private var updateChannel: FlutterMethodChannel?
  private weak var viewController: UIViewController?

  /// 外部 App「用 DSH Remote 打开 / 分享到 DSH Remote」进来的文档。
  /// 引擎未就绪、或 Dart 侧 handler 尚未注册时先攥在手里，等就绪后投递；
  /// Dart 首帧后也会主动 getIncomingFile 拉一次（只读不清，清空权在 clearIncomingFile）。
  private var pendingDoc: [String: Any]?
  /// 去重：投递成功置 true，Dart 侧 clearIncomingFile 后复位；避免同一文档弹两次。
  private var docDelivered = false
  /// 暂存代际号：防止旧文档的延迟释放定时器误清掉新文档。
  private var pendingDocGeneration: UInt64 = 0
  /// 系统文件选择器的回调（同一时刻只允许一个选择器）。
  private var pendingPickResult: FlutterResult?

  // MARK: - 注册

  func attach(registrar: FlutterPluginRegistrar) {
    viewController = registrar.viewController
    let messenger = registrar.messenger()

    let files = FlutterMethodChannel(name: DshNativeBridge.filesChannelName, binaryMessenger: messenger)
    files.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterMethodNotImplemented)
        return
      }
      self.handleFiles(call, result: result)
    }
    filesChannel = files

    let update = FlutterMethodChannel(name: DshNativeBridge.updateChannelName, binaryMessenger: messenger)
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
  /// 因为 Dart 侧会把它直接拼进 toast）。例："DSH-Remote/报告.docx"。
  private func saveToDownloads(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any] else {
      result(FlutterError(code: "bad-args", message: "missing arguments", details: nil))
      return
    }
    let name = DshNativeBridge.sanitizedFileName((args["name"] as? String) ?? "file")
    guard let typed = args["bytes"] as? FlutterStandardTypedData else {
      result(FlutterError(code: "bad-args", message: "missing bytes", details: nil))
      return
    }
    do {
      let dir = try documentsDirectory().appendingPathComponent(DshNativeBridge.savedFolderName, isDirectory: true)
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      let fileURL = dir.appendingPathComponent(name)
      try typed.data.write(to: fileURL, options: .atomic)
      // 可选：Dart 侧传 share=true 时弹系统分享面板（不阻塞 result，toast 立即返回）。
      if (args["share"] as? Bool) == true {
        presentShareSheet(for: fileURL)
      }
      // 只返回「DSH-Remote/文件名」这种人类可读相对位置：Dart 侧 iOS 文案会拼成
      // 「已保存到 App 文稿：DSH-Remote/xxx（可在「文件」App 查看）」，不要重复前缀、也不要暴露沙盒绝对路径。
      result("\(DshNativeBridge.savedFolderName)/\(name)")
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
    guard let presenter = presentingViewController(),
          presenter.viewIfLoaded?.window != nil,
          presenter.presentedViewController == nil
    else {
      // 没有可用 presenter（opening 转场中 / App 不可见）：立刻回报，避免 Dart await 永久挂起。
      result(FlutterError(code: "pick-failed", message: "no presenter available", details: nil))
      return
    }
    // 去掉 .item（public.item 含文件夹），避免用户选中文件夹后读取失败。
    let picker = UIDocumentPickerViewController(
      forOpeningContentTypes: [.data, .text, .image, .movie],
      asCopy: true
    )
    picker.delegate = self
    picker.allowsMultipleSelection = false
    pendingPickResult = result
    presenter.present(picker, animated: true)
    // present 在转场中/视图不在层级上时可能静默失败：短延迟校验，失败则回报并复位，
    // 防止一次性失败后 pendingPickResult 永久占用导致之后每次 pickFile 都 busy。
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self, weak picker] in
      guard let self, let picker, let completion = self.pendingPickResult else { return }
      guard picker.presentingViewController == nil else { return }
      self.pendingPickResult = nil
      completion(FlutterError(code: "pick-failed", message: "document picker was not presented", details: nil))
    }
  }

  // MARK: - UIDocumentPickerDelegate

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let completion = pendingPickResult else { return }
    pendingPickResult = nil
    guard let url = urls.first else {
      completion(nil)
      return
    }
    let name = url.lastPathComponent.isEmpty ? "file" : url.lastPathComponent
    // 读文件放到后台队列（iCloud 占位文件可能触发下载），读完回主线程回调，
    // 避免大文件解析阻塞主线程导致 UI 卡顿/看门狗误判。
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        guard let data = try DshNativeBridge.readDocument(at: url, maxBytes: DshNativeBridge.maxDocBytes) else {
          DispatchQueue.main.async {
            completion(FlutterError(
              code: "too-large",
              message: "file exceeds \(DshNativeBridge.maxDocBytes / (1024 * 1024))MB limit",
              details: nil
            ))
          }
          return
        }
        guard !data.isEmpty else {
          DispatchQueue.main.async {
            completion(FlutterError(code: "read-failed", message: "empty file", details: nil))
          }
          return
        }
        let payload: [String: Any] = [
          "name": name,
          "bytes": FlutterStandardTypedData(bytes: data),
        ]
        DispatchQueue.main.async { completion(payload) }
      } catch {
        DispatchQueue.main.async {
          completion(FlutterError(code: "read-failed", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    let completion = pendingPickResult
    pendingPickResult = nil
    completion?(nil)
  }

  // MARK: - 外部文档打开（file:// / security-scoped URL）

  /// 处理系统投递进来的外部文档 URL；返回是否已识别为文档。
  ///
  /// 注意：读字节在后台队列完成，冷启动时系统回调不会等读盘，避免阻塞主线程。
  @discardableResult
  func handleIncomingURL(_ url: URL) -> Bool {
    guard url.isFileURL else { return false }
    let name = url.lastPathComponent.isEmpty ? "document" : url.lastPathComponent
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self else { return }
      do {
        guard let data = try DshNativeBridge.readDocument(at: url, maxBytes: DshNativeBridge.maxDocBytes) else {
          self.storeIncomingDoc(name: name, error: "too-large")
          return
        }
        if data.isEmpty {
          self.storeIncomingDoc(name: name, error: "empty")
        } else {
          self.storeIncomingDoc(name: name, bytes: data)
        }
      } catch {
        // 读失败也要投给 Dart：用户点了「用 DSH Remote 打开」却毫无反应会以为 App 坏了。
        self.storeIncomingDoc(name: name, error: error.localizedDescription)
      }
    }
    return true
  }

  /// 暂存外部文档（主线程），并尝试投递。bytes 为空表示只带 error。
  private func storeIncomingDoc(name: String, bytes: Data? = nil, error: String? = nil) {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      DshNativeBridge.assertMainThread()
      var payload: [String: Any] = ["name": name]
      if let error {
        payload["error"] = error
      }
      if let bytes {
        payload["bytes"] = FlutterStandardTypedData(bytes: bytes)
      }
      self.pendingDoc = payload
      self.docDelivered = false
      self.pendingDocGeneration &+= 1
      self.deliverPendingDoc()
    }
  }

  /// 把暂存文档投给 Dart（引擎/通道未就绪时 no-op，等 attach 后再补投）。
  private func deliverPendingDoc() {
    guard let doc = pendingDoc, let channel = filesChannel, !docDelivered else { return }
    docDelivered = true
    let generation = pendingDocGeneration
    channel.invokeMethod("openDocument", arguments: doc)
    // invokeMethod 只是入队，不保证 Dart 已注册 handler；Dart 首帧会 getIncomingFile 兜底。
    // 宽限到期仍未消费（未收到 clearIncomingFile）就释放暂存字节，避免大文件常驻内存。
    DispatchQueue.main.asyncAfter(deadline: .now() + DshNativeBridge.pendingDocReleaseDelay) { [weak self] in
      guard let self else { return }
      guard self.pendingDocGeneration == generation, self.docDelivered else { return }
      self.pendingDoc = nil
    }
  }

  // MARK: - Helpers

  /// 读取外部文档字节（线程安全，可在后台队列调用）。
  /// 返回 nil 表示超过大小上限（不读内容）。
  private static func readDocument(at url: URL, maxBytes: Int) throws -> Data? {
    // iCloud / 其他 App 的文件是 security-scoped URL，先取访问权限（读失败则放弃权限申请结果）。
    let scoped = url.startAccessingSecurityScopedResource()
    defer {
      if scoped { url.stopAccessingSecurityScopedResource() }
    }
    // 先看元数据大小，能避免 iCloud 未下载的大文件触发整份下载/读取。
    if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size > maxBytes {
      return nil
    }
    let data = try Data(contentsOf: url, options: .mappedIfSafe)
    return data.count > maxBytes ? nil : data
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
    guard let presenter = presentingViewController(),
          presenter.viewIfLoaded?.window != nil,
          presenter.presentedViewController == nil
    else {
      return
    }
    let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
    if let popover = activity.popoverPresentationController {
      popover.sourceView = presenter.view
      popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
    }
    presenter.present(activity, animated: true)
  }

  private static func assertMainThread() {
    assert(Thread.isMainThread, "DshNativeBridge 状态必须在主线程访问")
  }
}