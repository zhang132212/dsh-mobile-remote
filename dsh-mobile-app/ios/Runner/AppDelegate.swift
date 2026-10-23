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