package com.dsh.remote

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.os.Bundle
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
 * 要回答的问题只有一个：华为「全局手写」认不认**原生 EditText**。
 *
 * 背景：Flutter 的 TextField 是自绘的，系统只看到一个隐藏的编辑代理——实测 MatePad 11
 * （HarmonyOS 4.2）在这上面开全局手写毫无反应，落笔被当成普通触摸。华为文档也写明
 * 「个别应用自定义的输入框」不支持。
 *
 * 判定：
 *  - 在这一页能用笔写出字 → 原生输入框这条链路通 → App 侧补丁成立：
 *    「手写模式」弹一层原生输入框，写完把文本回传给 Flutter 的 composer。
 *  - 这一页也写不出 → 连原生都不认（华为按包名/窗口判定），只能改走自建手写板。
 */
class HandwritingProbeActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val d = resources.displayMetrics.density
        fun dp(v: Int) = (v * d).toInt()

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(28), dp(20), dp(20))
            setBackgroundColor(Color.parseColor("#0E1116"))
        }

        root.addView(TextView(this).apply {
            text = "手写笔探针"
            setTextColor(Color.WHITE)
            textSize = 20f
        })

        root.addView(TextView(this).apply {
            text = "用 M-Pencil 直接在下面的框里写。\n出字 = 系统全局手写认原生输入框，补丁路径成立；\n完全没反应 = 连原生都不认，得换自建手写板。"
            setTextColor(Color.parseColor("#8B96A5"))
            textSize = 13f
            setPadding(0, dp(10), 0, dp(14))
        })

        val edit = EditText(this).apply {
            hint = "在这里写…"
            setHintTextColor(Color.parseColor("#5B6472"))
            setTextColor(Color.WHITE)
            textSize = 22f
            gravity = Gravity.TOP
            minLines = 8
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
        window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
        edit.requestFocus()
        // 输入法面板要"活着"，全局手写才有落笔判定；延迟一拍等窗口稳定
        edit.postDelayed({
            (getSystemService(INPUT_METHOD_SERVICE) as? InputMethodManager)
                ?.showSoftInput(edit, InputMethodManager.SHOW_IMPLICIT)
        }, 250)
    }

    companion object {
        const val EXTRA_TEXT = "text"
    }
}
