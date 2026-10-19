package com.dsh.remote

import android.annotation.SuppressLint
import android.app.Activity
import android.app.AlertDialog
import android.os.Bundle
import android.text.InputType
import android.view.ViewGroup
import android.webkit.JsPromptResult
import android.webkit.JsResult
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.EditText
import android.widget.FrameLayout
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

/**
 * HTML 交互模式（v3.2.13）——原生 WebView，让 HTML 里 JS 设计的按钮真的能点。
 *
 * 静态阅读页只做「读」；这里补上「用」：真浏览器引擎跑 JS。
 *  · http(s) 文档：直接加载 URL（完整网页能力）；
 *  · 电脑工作区的本地 HTML：正文灌进 WebView（虚拟基址 https://dsh-remote.local/），
 *    页面里相对路径的 JS / CSS / 图片由 shouldInterceptRequest 按文档所在目录、
 *    经电脑端 /m/api/files 拉取——依赖脚本的按钮也能正常工作。
 *
 * 安全边界：不开 addJavascriptInterface、不开 file:// 访问；只暴露一个虚拟主机的
 * 资源拦截，且路径必须落在文档所在目录内（阻止 ../ 越界）。
 */
class HtmlViewerActivity : Activity() {
    private lateinit var webView: WebView

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        webView = WebView(this)
        val root = FrameLayout(this)
        root.addView(
            webView,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )
        setContentView(root)
        webView.setBackgroundColor(0xFFFFFFFF.toInt())

        webView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            allowFileAccess = false
            allowContentAccess = false
            javaScriptCanOpenWindowsAutomatically = false
            mediaPlaybackRequiresUserGesture = true
            cacheMode = WebSettings.LOAD_DEFAULT
            builtInZoomControls = true
            displayZoomControls = false
            useWideViewPort = true
            loadWithOverviewMode = true
            setSupportZoom(true)
        }

        // JS 弹窗：WebView 默认不会自己弹，必须由宿主代为显示，否则 alert/confirm 会卡住脚本。
        webView.webChromeClient = object : WebChromeClient() {
            override fun onJsAlert(view: WebView, url: String?, message: String?, result: JsResult?): Boolean {
                AlertDialog.Builder(this@HtmlViewerActivity)
                    .setMessage(message)
                    .setPositiveButton("OK") { _, _ -> result?.confirm() }
                    .setOnCancelListener { result?.cancel() }
                    .show()
                return true
            }

            override fun onJsConfirm(view: WebView, url: String?, message: String?, result: JsResult?): Boolean {
                AlertDialog.Builder(this@HtmlViewerActivity)
                    .setMessage(message)
                    .setPositiveButton("OK") { _, _ -> result?.confirm() }
                    .setNegativeButton("Cancel") { _, _ -> result?.cancel() }
                    .setOnCancelListener { result?.cancel() }
                    .show()
                return true
            }

            override fun onJsPrompt(
                view: WebView,
                url: String?,
                message: String?,
                defaultValue: String?,
                result: JsPromptResult?,
            ): Boolean {
                val input = EditText(this@HtmlViewerActivity).apply {
                    setText(defaultValue ?: "")
                    inputType = InputType.TYPE_CLASS_TEXT
                }
                AlertDialog.Builder(this@HtmlViewerActivity)
                    .setMessage(message)
                    .setView(input)
                    .setPositiveButton("OK") { _, _ -> result?.confirm(input.text.toString()) }
                    .setNegativeButton("Cancel") { _, _ -> result?.cancel() }
                    .setOnCancelListener { result?.cancel() }
                    .show()
                return true
            }
        }

        val url = intent.getStringExtra("url")
        val html = intent.getStringExtra("html")
        if (!url.isNullOrEmpty()) {
            webView.webViewClient = WebViewClient()
            webView.loadUrl(url)
            return
        }
        if (html == null) {
            finish()
            return
        }

        val baseDir = intent.getStringExtra("baseDir")
        val apiBase = intent.getStringExtra("apiBase")
        val token = intent.getStringExtra("token")
        webView.webViewClient =
            if (!baseDir.isNullOrEmpty() && !apiBase.isNullOrEmpty() && !token.isNullOrEmpty()) {
                PcAssetClient(apiBase, token, baseDir)
            } else {
                WebViewClient()
            }
        webView.loadDataWithBaseURL(VIRTUAL_BASE, html, "text/html", "utf-8", null)
    }

    override fun onBackPressed() {
        if (::webView.isInitialized && webView.canGoBack()) {
            webView.goBack()
        } else {
            super.onBackPressed()
        }
    }

    override fun onDestroy() {
        if (::webView.isInitialized) {
            webView.destroy()
        }
        super.onDestroy()
    }

    /** 把虚拟主机上的相对资源请求映射到「电脑上的文档目录 + /m/api/files」。 */
    private inner class PcAssetClient(
        private val apiBase: String,
        private val token: String,
        private val baseDir: String,
    ) : WebViewClient() {
        override fun shouldInterceptRequest(
            view: WebView,
            request: WebResourceRequest,
        ): WebResourceResponse? {
            val uri = request.url
            if (uri.host != VIRTUAL_HOST) return null
            val rel = uri.path?.trimStart('/') ?: return null
            if (rel.isEmpty()) return null
            return try {
                val base = File(baseDir).canonicalFile
                val target = File(base, rel.replace('/', File.separatorChar)).canonicalFile
                val basePath = base.path.lowercase()
                val targetPath = target.path.lowercase()
                if (!targetPath.startsWith(basePath)) return null
                if (!target.isFile) return null
                val encoded = URLEncoder.encode(target.path, "UTF-8")
                val conn = URL("$apiBase/api/files?path=$encoded").openConnection() as HttpURLConnection
                conn.setRequestProperty("X-Mobile-Token", token)
                conn.connectTimeout = 8000
                conn.readTimeout = 20000
                if (conn.responseCode != 200) {
                    conn.disconnect()
                    return null
                }
                WebResourceResponse(
                    mimeOf(target.name),
                    null,
                    conn.responseCode,
                    "OK",
                    emptyMap<String, String>(),
                    conn.inputStream,
                )
            } catch (e: Exception) {
                null
            }
        }
    }

    private fun mimeOf(name: String): String =
        when (name.substringAfterLast('.', "").lowercase()) {
            "html", "htm" -> "text/html"
            "js", "mjs" -> "application/javascript"
            "css" -> "text/css"
            "json" -> "application/json"
            "svg" -> "image/svg+xml"
            "png" -> "image/png"
            "jpg", "jpeg" -> "image/jpeg"
            "gif" -> "image/gif"
            "webp" -> "image/webp"
            "ico" -> "image/x-icon"
            "woff" -> "font/woff"
            "woff2" -> "font/woff2"
            "ttf" -> "font/ttf"
            "otf" -> "font/otf"
            "wasm" -> "application/wasm"
            else -> "application/octet-stream"
        }

    companion object {
        private const val VIRTUAL_HOST = "dsh-remote.local"
        private const val VIRTUAL_BASE = "https://dsh-remote.local/"
    }
}
