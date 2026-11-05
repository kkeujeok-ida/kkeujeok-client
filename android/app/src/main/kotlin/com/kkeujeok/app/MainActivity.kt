package com.kkeujeok.app

import android.app.LocaleManager
import android.content.Intent
import android.graphics.Rect
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import android.os.Build
import android.os.LocaleList
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    // A PDF another app opened or shared with us; Dart takes it once it is ready
    // (after sign-in), so it is kept here until then.
    private var pendingPdf: Uri? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // A recreated activity gets its old intent again: not a new share.
        if (savedInstanceState == null) takePdfIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        takePdfIntent(intent)
    }

    private fun takePdfIntent(intent: Intent?) {
        if (intent == null) return
        val uri: Uri? = when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND ->
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU)
                    intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                else @Suppress("DEPRECATION") intent.getParcelableExtra(Intent.EXTRA_STREAM)
            else -> null
        }
        if (uri != null) pendingPdf = uri
    }

    private fun displayName(uri: Uri): String {
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
            if (it.moveToFirst()) it.getString(0)?.let { n -> return n }
        }
        return uri.lastPathSegment?.substringAfterLast('/') ?: "document.pdf"
    }

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

        // The PDF another app opened or shared: copied to the cache folder (a
        // stream copy, off the main thread) and handed over once.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.kkeujeok.app/pdf")
            .setMethodCallHandler { call, result ->
                if (call.method != "takePending") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val uri = pendingPdf
                pendingPdf = null
                if (uri == null) {
                    result.success(null)
                    return@setMethodCallHandler
                }
                Thread {
                    try {
                        val name = displayName(uri)
                        val dir = File(cacheDir, "shared_pdf").apply { mkdirs() }
                        val out = File(dir, "shared.pdf")
                        contentResolver.openInputStream(uri)!!.use { i ->
                            out.outputStream().use { o -> i.copyTo(o) }
                        }
                        runOnUiThread { result.success(mapOf("path" to out.path, "name" to name)) }
                    } catch (e: Exception) {
                        runOnUiThread { result.error("pdf", e.message, null) }
                    }
                }.start()
            }
    }
}
