package com.kkeujeok.app

import android.app.LocaleManager
import android.graphics.Rect
import android.os.Build
import android.os.LocaleList
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Mirrors the in-app language choice into the system per-app language
        // setting (API 33+). A null tag clears it, i.e. "follow system".
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.kkeujeok.app/locale")
            .setMethodCallHandler { call, result ->
                if (call.method != "setApplicationLocales") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    try {
                        val tag = call.arguments as String?
                        getSystemService(LocaleManager::class.java).applicationLocales =
                            if (tag == null) LocaleList.getEmptyLocaleList()
                            else LocaleList.forLanguageTags(tag)
                    } catch (e: Exception) {
                        result.error("locale", e.message, null)
                        return@setMethodCallHandler
                    }
                }
                result.success(null)
            }

        // Keeps the system back gesture off the given screen-pixel rects
        // (an empty list lifts it).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.kkeujeok.app/gesture")
            .setMethodCallHandler { call, result ->
                if (call.method != "setExclusionRects") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                try {
                    val rects = (call.arguments as List<*>).map { r ->
                        val v = (r as List<*>).map { (it as Number).toInt() }
                        Rect(v[0], v[1], v[2], v[3])
                    }
                    window.decorView.systemGestureExclusionRects = rects
                    result.success(null)
                } catch (e: Exception) {
                    result.error("gesture", e.message, null)
                }
            }
    }
}
