package com.dsh.remote

import android.content.Intent
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var floatingChannel: MethodChannel? = null
    private var filesChannel: MethodChannel? = null
    // v3.1.2（csborbbnc 反馈）：系统文件选择器（ACTION_OPEN_DOCUMENT）结果回传暂存
    private var pendingPick: MethodChannel.Result? = null
    private val pickFileRequestCode = 2001
    // v2.7.2 review(FS1)：悬浮球面板动作可能发生在冷启动（进程已被系统杀死时点"打开会话/充值/通知"），
    // 此时走 onCreate 而非 onNewIntent；Flutter 引擎未就绪前先暂存，configureFlutterEngine 后再投递。
    private var pendingOpenAction: String? = null // "charge" | "usage" | "notifs" | "session:<id>"
    // v3.2.0：外部 App「用本 App 打开 / 分享到本 App」进来的文档。
    // 与上面的面板动作同一个理由：冷启动时 intent 早于 Flutter 引擎就绪，
    // 原生侧先把 {name, bytes} 攥在手里，configureFlutterEngine 之后再投给 Dart。
    private var pendingDoc: HashMap<String, Any>? = null
    // 去重标记：onCreate / configureFlutterEngine / onNewIntent 三条路径都会尝试投递，
    // 不去重会把同一个文档弹两遍；Dart 侧调 clearIncomingFile 确认消费完才复位。
    private var docDelivered = false

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        // v2.9.0 review(A2)：Android 13+ 运行时请求通知权限（manifest 已声明 POST_NOTIFICATIONS）——
        // 不请求则悬浮球"运行中/点击回到 App"前台服务通知被系统抑制，用户看不到常驻提示
        if (Build.VERSION.SDK_INT >= 33) {
            if (checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) !=
                android.content.pm.PackageManager.PERMISSION_GRANTED
            ) {
                requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 1001)
            }
        }
        handleIntentExtras(intent)
        // v3.2.0：外部「打开方式」冷启动——进程被系统杀死后点文件进 App 走的是这里
        handleDocIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        floatingChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dsh/floating")
        // v3.1.2（csborbbnc 反馈）：文件下载/上传原生通道
        filesChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dsh/files")
        filesChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "saveToDownloads" -> {
                    val name = call.argument<String>("name") ?: "file"
                    val bytes = call.argument<ByteArray>("bytes")
                    if (bytes == null) {
                        result.error("bad-args", "missing bytes", null)
                        return@setMethodCallHandler
                    }
                    saveToDownloads(name, bytes, result)
                }
                "pickFile" -> pickFile(result)
                // v3.2.0：投递过的文档可能早于 Dart 侧 handler 注册——Dart 首帧后主动拉取一份兜底。
                // 只读不清：清空权交给 clearIncomingFile，避免「投递失败 + 已置空」导致文档丢失。
                "getIncomingFile" -> result.success(pendingDoc)
                "clearIncomingFile" -> {
                    pendingDoc = null
                    docDelivered = false
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
        // 引擎就绪：投递冷启动暂存的面板动作
        deliverPendingAction()
        // v2.7.2 review：Dart 侧 handler 注册可能晚于本回调——延迟再投一次 + consume 兜底
        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({ deliverPendingAction() }, 800)
        floatingChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    startBubbleService()
                    result.success(true)
                }
                "stop" -> {
                    stopService(Intent(this, FloatingBubbleService::class.java))
                    result.success(true)
                }
                "isRunning" -> result.success(FloatingBubbleService.running)
                "canDrawOverlay" -> result.success(Settings.canDrawOverlays(this))
                "openOverlaySettings" -> {
                    openOverlaySettingsPage()
                    result.success(true)
                }
                // v2.7.2 review：冷启动动作兜底——Dart 首帧后主动拉取（投递失败时动作不丢）
                "consumeOpenPanel" -> {
                    result.success(pendingOpenAction)
                    pendingOpenAction = null
                }
                "notifyBalance" -> {
                    val v = call.argument<String>("value") ?: ""
                    // 服务未运行时忽略（否则余额刷新会把悬浮球拉起来，开关形同虚设）
                    if (FloatingBubbleService.running) {
                        val i = Intent(this, FloatingBubbleService::class.java).putExtra("balance", v)
                        startServiceCompat(i)
                    }
                    result.success(true)
                }
                "setBalanceAlert" -> {
                    // 余额预警配置（开关 + 阈值）推给悬浮球：悬浮球的报警判定完全以 App 端设置为依据
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    val threshold = call.argument<String>("threshold")?.toDoubleOrNull() ?: 10.0
                    if (FloatingBubbleService.running) {
                        val i = Intent(this, FloatingBubbleService::class.java)
                            .putExtra("alert_enabled", enabled)
                            .putExtra("alert_threshold", threshold)
                        startServiceCompat(i)
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
        // v3.2.0：冷启动时 intent 先于引擎到达，handleDocIntent 投递是 no-op——这里补投一次；
        // 若 intent 来得更晚（onNewIntent），此调用只是空转，docDelivered 保证不会重复弹。
        deliverPendingDoc()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // 悬浮球迷你面板动作（热启动路径）：暂存后投递（引擎就绪时立即生效）
        handleIntentExtras(intent)
        // v3.2.0：singleTop + 已在栈顶时再点一个文件走这里（不重建 Activity，只有 onNewIntent）
        handleDocIntent(intent)
    }

    /** 解析悬浮球面板动作 extra；onCreate（冷启动）与 onNewIntent（热启动）共用。 */
    private fun handleIntentExtras(intent: Intent?) {        if (intent == null) return
        when {
            intent.getBooleanExtra("open_charge", false) -> pendingOpenAction = "charge"
            intent.getBooleanExtra("open_usage", false) -> pendingOpenAction = "usage"
            intent.getBooleanExtra("open_notifs", false) -> pendingOpenAction = "notifs"
            else -> intent.getStringExtra("open_session")?.let { pendingOpenAction = "session:$it" }
        }
        deliverPendingAction()
    }

    /** 投递暂存的面板动作到 Flutter 侧（引擎未就绪时 no-op，等 configureFlutterEngine 再投）。 */
    private fun deliverPendingAction() {
        val action = pendingOpenAction ?: return
        val ch = floatingChannel ?: return
        when {
            action == "charge" -> ch.invokeMethod("openChargeRequested", null)
            action == "usage" -> ch.invokeMethod("openUsageRequested", null)
            action == "notifs" -> ch.invokeMethod("openNotifsRequested", null)
            action.startsWith("session:") -> {
                val sid = action.removePrefix("session:")
                if (sid.isNotEmpty()) ch.invokeMethod("openSessionRequested", sid)
            }
        }
        pendingOpenAction = null
    }

    // ── v3.2.0：外部「用本 App 打开 / 分享到本 App」的文档 ──────────────────
    /**
     * 解析外部传入的文档 intent，读成 {name, bytes} 暂存；onCreate（冷启动）与 onNewIntent（热启动）共用。
     * 原生侧不解析文档格式（md/docx/xlsx 都只是字节），解析与渲染全交给 Dart 侧。
     */
    @Suppress("DEPRECATION")
    private fun handleDocIntent(intent: Intent?) {
        if (intent == null) return
        // ACTION_VIEW = 文件管理器点「打开方式」（uri 在 data）；
        // 其余（ACTION_SEND 分享）uri 挂在 EXTRA_STREAM 上（微信/QQ 的「分享到」走这条）。
        // 单参泛型 getParcelableExtra 自 API 33 起标记弃用但并未移除（android-35/36 的 android.jar 实测仍在），
        // 这里显式写出泛型实参，绕开类型推导，任何 compileSdk 下都稳。
        val stream = intent.getParcelableExtra<android.net.Uri>(Intent.EXTRA_STREAM)
        val uri: android.net.Uri? = if (intent.action == Intent.ACTION_VIEW) intent.data else stream
        if (uri == null) return
        val name = queryDisplayName(uri) ?: (uri.lastPathSegment ?: "document")
        val bytes = try {
            contentResolver.openInputStream(uri)?.use { it.readBytes() }
        } catch (e: Exception) {
            // 权限不足 / 分享的临时 uri 已过期 / 网盘链接失效都会走到这里。
            // **不能静默 return**：用户点了「用 DSH Remote 打开」却毫无反应，会以为 App 坏了。
            // 把失败也投递给 Dart，由前端给出可读提示（Dart 侧见 _openIncomingDoc 的 error 分支）。
            pendingDoc = hashMapOf<String, Any>(
                "name" to name,
                "error" to (e.message ?: e.javaClass.simpleName),
            )
            deliverPendingDoc()
            return
        }
        if (bytes == null || bytes.isEmpty()) {
            pendingDoc = hashMapOf<String, Any>("name" to name, "error" to "empty")
            deliverPendingDoc()
            return
        }
        pendingDoc = hashMapOf<String, Any>("name" to name, "bytes" to bytes)
        deliverPendingDoc()
    }

    /** 投递暂存的文档到 Flutter 侧（引擎未就绪时 no-op，等 configureFlutterEngine 再投）。 */
    private fun deliverPendingDoc() {
        val doc = pendingDoc ?: return
        val ch = filesChannel ?: return
        // 已投递过就不再投：冷启动 + 热启动路径叠加时会弹两次同一个文档
        if (docDelivered) return
        ch.invokeMethod("openDocument", doc)
        docDelivered = true
    }

    private fun startBubbleService() {
        val i = Intent(this, FloatingBubbleService::class.java)
        startServiceCompat(i)
    }

    private fun startServiceCompat(i: Intent) {
        if (Build.VERSION.SDK_INT >= 26) {
            startForegroundService(i)
        } else {
            startService(i)
        }
    }

    private fun openOverlaySettingsPage() {
        try {
            val i = Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                android.net.Uri.parse("package:$packageName")
            )
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(i)
        } catch (e: Exception) {
            val i = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION)
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(i)
        }
    }

    // ── v3.1.2（csborbbnc 反馈）：文件保存 / 系统文件选择器 ──────────────────
    /** 保存到系统「下载」目录：Android 10+ 用 MediaStore（免权限）；更早版本退到应用下载目录。 */
    private fun saveToDownloads(name: String, bytes: ByteArray, result: MethodChannel.Result) {
        try {
            if (Build.VERSION.SDK_INT >= 29) {
                val values = android.content.ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                    put(MediaStore.MediaColumns.MIME_TYPE, mimeOf(name))
                    put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/DSH-Remote")
                }
                val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                    ?: throw IllegalStateException("MediaStore insert failed")
                contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
                    ?: throw IllegalStateException("openOutputStream failed")
                result.success("Download/DSH-Remote/$name")
            } else {
                val dir = getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
                val f = File(dir, name)
                f.writeBytes(bytes)
                result.success("Android/data/com.dsh.remote/files/Download/$name")
            }
        } catch (e: Exception) {
            result.error("save-failed", e.message ?: "save failed", null)
        }
    }

    /** 系统文件选择器（ACTION_OPEN_DOCUMENT），结果经 onActivityResult 回传 {name, bytes}。 */
    private fun pickFile(result: MethodChannel.Result) {
        if (pendingPick != null) {
            result.error("busy", "already picking", null)
            return
        }
        pendingPick = result
        startActivityForResult(
            Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "*/*"
            },
            pickFileRequestCode,
        )
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == pickFileRequestCode) {
            val res = pendingPick
            pendingPick = null
            if (resultCode == RESULT_OK && data?.data != null) {
                val uri = data.data!!
                try {
                    val name = queryDisplayName(uri) ?: "file"
                    val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() } ?: byteArrayOf()
                    res?.success(hashMapOf("name" to name, "bytes" to bytes))
                } catch (e: Exception) {
                    res?.error("read-failed", e.message ?: "read failed", null)
                }
            } else {
                res?.error("cancelled", null, null)
            }
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun queryDisplayName(uri: android.net.Uri): String? {
        contentResolver.query(uri, null, null, null, null)?.use { c ->
            val i = c.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
            if (i >= 0 && c.moveToFirst()) return c.getString(i)
        }
        return uri.lastPathSegment
    }

    private fun mimeOf(name: String): String = when (name.substringAfterLast('.', "").lowercase()) {
        "txt", "md", "log" -> "text/plain"
        "json" -> "application/json"
        "pdf" -> "application/pdf"
        "png" -> "image/png"
        "jpg", "jpeg" -> "image/jpeg"
        "gif" -> "image/gif"
        "webp" -> "image/webp"
        "zip" -> "application/zip"
        "mp4" -> "video/mp4"
        else -> "application/octet-stream"
    }
}
