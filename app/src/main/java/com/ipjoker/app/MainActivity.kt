package com.ipjoker.app

import android.app.Activity
import android.os.Bundle
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebView
import android.webkit.WebViewClient
import org.json.JSONArray
import org.json.JSONObject

class MainActivity : Activity() {
    private lateinit var web: WebView
    private val prefs by lazy { getSharedPreferences("ipjoker", MODE_PRIVATE) }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        web = WebView(this)
        web.settings.javaScriptEnabled = true
        web.settings.domStorageEnabled = true
        web.webViewClient = WebViewClient()
        web.webChromeClient = WebChromeClient()
        web.addJavascriptInterface(NativeBridge(), "IPJokerVPN")
        setContentView(web)
        web.loadUrl("file:///android_asset/index.html")
    }

    inner class NativeBridge {
        @JavascriptInterface fun connect(host: String, port: String, type: String): String =
            JSONObject().put("ok", false)
                .put("message", "موتور تونل هنوز در این نسخه یکپارچه نشده است.")
                .toString()

        @JavascriptInterface fun disconnect(): String =
            JSONObject().put("ok", true).put("message", "اتصالی برقرار نشده است.").toString()

        @JavascriptInterface fun getStatus(): String =
            JSONObject().put("connected", false).put("engineReady", false).toString()

        @JavascriptInterface fun saveCurrentProfile(host: String, port: String, type: String) {
            prefs.edit().putString("last_host", host).putString("last_port", port)
                .putString("last_type", type).apply()
        }

        @JavascriptInterface fun getSavedProfiles(): String =
            JSONArray().toString()
    }
}
