package com.kkeujeok.app

import android.app.LocaleManager
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
    }
}
