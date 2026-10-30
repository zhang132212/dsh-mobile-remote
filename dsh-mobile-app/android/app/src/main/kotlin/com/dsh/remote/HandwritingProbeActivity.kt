package com.dsh.remote

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.text.InputType
import android.view.Gravity
import android.view.ViewGroup
import android.view.WindowManager
import android.view.inputmethod.InputMethodManager
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView

/**
 * v3.3.1 手写笔探针（实验页，只由 App 内部拉起）。
 *
 * 要回答的问题：华为「全局手写」认不认**原生 EditText**。
 *
 * 第一版探针（3.2.17）在 MatePad 11 上的结果：落笔被当成长按，弹出「选取文字 / 复制粘贴」，
 * 手写完全没被触发。这个结果有两种解释，必须分开：
 *   1) 输入法面板压根没起来 —— 全局手写依附在 IME 上，没有 IME 就只剩普通触摸（探针的锅）；
 *   2) 系统对这个应用不启用全局手写（系统的锅）。
 * 所以这一版把「输入法是否真的在」显式画出来，并提供手动唤起按钮。
 */
class HandwritingProbeActivity : Activity() {
    private lateinit var edit: EditText
    private lateinit var status: TextView
    private val ui = Handler(Looper.getMainLooper())

    private val tick = object : Runnable {
        override fun run() {
            status.text = statusLine()
            ui.postDelayed(this, 400)
        }
    }

    private fun imeName(): String {
        val id = Settings.Secure.getString(contentResolver, Settings.Secure.DEFAULT_INPUT_METHOD) ?: "?"
        return id.substringBefore('/')
    }

    /** 用可见区域差估算键盘高度：差 > 120dp 视为输入法面板在场。 */
    private fun imeShown(): Boolean {
        val r = android.graphics.Rect()
        window.decorView.getWindowVisibleDisplayFrame(r)
        val full = resources.displayMetrics.heightPixels
        val gap = full - r.bottom
        return gap > (120 * resources.displayMetrics.density).toInt()
    }

    private fun statusLine(): String {
        val flag = if (imeShown()) "输入法面板：在" else "输入法面板：不在"
        val focus = if (edit.hasFocus()) "已聚焦" else "未聚焦"
        return "$flag ｜ $focus\n当前输入法：${imeName()}"
    }

    private fun showIme() {
        edit.requestFocus()
        val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager ?: return
        imm.showSoftInput(edit, InputMethodManager.SHOW_IMPLICIT)
        ui.postDelayed({
            status.text = statusLine()
        }, 300)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // 关键：让窗口一出现就"要"输入法，而不是等用户点
        window.setSoftInputMode(
            WindowManager.LayoutParams.SOFT_INPUT_STATE_VISIBLE or
                WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE,
        )

        val d = resources.displayMetrics.density
        fun dp(v: Int) = (v * d).toInt()

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(28), dp(20), dp(20))
            setBackgroundColor(Color.parseColor("#0E1116"))
        }

        root.addView(TextView(this).apply {
            text = "手写笔探针 v2"
            setTextColor(Color.WHITE)
            textSize = 20f
        })

        root.addView(TextView(this).apply {
            text = "先确认下面这行写着「输入法面板：在」。\n不在就点「显示键盘」，等它起来，再用笔在框里写。\n能出字 = 全局手写认原生输入框；仍是长按/选区 = 系统没启用。"
            setTextColor(Color.parseColor("#8B96A5"))
            textSize = 13f
            setPadding(0, dp(10), 0, dp(8))
        })

        status = TextView(this).apply {
            text = "…"
            setTextColor(Color.parseColor("#5FD3A6"))
            textSize = 12f
            setPadding(0, 0, 0, dp(10))
        }
        root.addView(status)

        edit = EditText(this).apply {
            hint = "在这里写…"
            setHintTextColor(Color.parseColor("#5B6472"))
            setTextColor(Color.WHITE)
            textSize = 22f
            gravity = Gravity.TOP
            minLines = 6
            isFocusableInTouchMode = true
            setShowSoftInputOnFocus(true)
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE
            setBackgroundColor(Color.parseColor("#171B21"))
            setPadding(dp(14), dp(14), dp(14), dp(14))
        }
        root.addView(edit, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))

        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(0, dp(14), 0, 0)
        }
        row.addView(Button(this).apply {
            text = "显示键盘"
            setOnClickListener { showIme() }
        }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        row.addView(Button(this).apply {
            text = "取消"
            setOnClickListener {
                setResult(RESULT_CANCELED)
                finish()
            }
        }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        row.addView(Button(this).apply {
            text = "完成"
            setOnClickListener {
                val out = Intent().putExtra(EXTRA_TEXT, edit.text?.toString() ?: "")
                setResult(RESULT_OK, out)
                finish()
            }
        }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        root.addView(row)

        setContentView(root)
        edit.requestFocus()
        // 首帧之后再要一次输入法：Activity 刚创建时 showSoftInput 常被系统丢弃
        edit.post { showIme() }
        edit.postDelayed({ showIme() }, 400)
    }

    override fun onResume() {
        super.onResume()
        ui.post(tick)
    }

    override fun onPause() {
        ui.removeCallbacks(tick)
        super.onPause()
    }

    companion object {
        const val EXTRA_TEXT = "text"
    }
}
