package cn.edu.neu.neu_portal

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.webkit.CookieManager
import android.Manifest
import android.content.pm.PackageManager
import java.net.URI
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

class MainActivity : FlutterActivity() {
    private val webPermissionRequestCode = 4101
    private var webPermissionResult: MethodChannel.Result? = null
    private var webPermissionResources = emptyList<String>()

    private fun hasWebPermissions(resources: List<String>): Boolean = resources.all { resource ->
        when (resource) {
            "camera" -> checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED
            "microphone" -> checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
            "location" -> checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
                checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
            else -> false
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != webPermissionRequestCode) return
        val result = webPermissionResult
        webPermissionResult = null
        result?.success(grantResults.isNotEmpty() && hasWebPermissions(webPermissionResources))
        webPermissionResources = emptyList()
    }

    override fun onDestroy() {
        webPermissionResult?.success(false)
        webPermissionResult = null
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "neu.portal/web_permissions")
            .setMethodCallHandler { call, result ->
                if (call.method != "request") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val resources = (call.arguments as? List<*>)?.filterIsInstance<String>() ?: emptyList()
                if (resources.isEmpty() || webPermissionResult != null ||
                    resources.any { it !in setOf("camera", "microphone", "location") }) {
                    result.success(false)
                    return@setMethodCallHandler
                }
                if (hasWebPermissions(resources)) {
                    result.success(true)
                    return@setMethodCallHandler
                }
                val permissions = resources.flatMap { resource ->
                    when (resource) {
                        "camera" -> listOf(Manifest.permission.CAMERA)
                        "microphone" -> listOf(Manifest.permission.RECORD_AUDIO)
                        "location" -> listOf(Manifest.permission.ACCESS_COARSE_LOCATION, Manifest.permission.ACCESS_FINE_LOCATION)
                        else -> emptyList()
                    }
                }.distinct().filter { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
                webPermissionResult = result
                webPermissionResources = resources
                try {
                    requestPermissions(permissions.toTypedArray(), webPermissionRequestCode)
                } catch (error: Exception) {
                    webPermissionResult = null
                    webPermissionResources = emptyList()
                    result.error("permission_request_failed", error.message, null)
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "neu.portal/session_cookies")
            .setMethodCallHandler { call, result ->
                val manager = CookieManager.getInstance()
                when (call.method) {
                    "read" -> {
                        val records = mutableListOf<Map<String, Any>>()
                        val seen = mutableSetOf<String>()
                        for (url in (call.arguments as? List<*>)?.filterIsInstance<String>() ?: emptyList()) {
                            val uri = URI(url)
                            for (pair in (manager.getCookie(url) ?: "").split(';')) {
                                val eq = pair.indexOf('=')
                                if (eq < 1) continue
                                val name = pair.substring(0, eq).trim()
                                val value = pair.substring(eq + 1).trim()
                                if (value.isEmpty() || !seen.add("${uri.host}|$name|$value")) continue
                                // Android exposes name/value only. Preserve known HTTP metadata in Dart.
                                records.add(mapOf("name" to name, "value" to value,
                                    "domain" to uri.host, "path" to (if (uri.path.isEmpty()) "/" else uri.path.substringBeforeLast('/') + "/"),
                                    "secure" to true, "httpOnly" to true, "hostOnly" to true,
                                    "metadataKnown" to false))
                            }
                        }
                        result.success(records)
                    }
                    "restore" -> {
                        val records = (call.arguments as? List<*>)?.filterIsInstance<Map<*, *>>() ?: emptyList()
                        var pending = records.size
                        if (pending == 0) { result.success(null); return@setMethodCallHandler }
                        fun finished() { pending--; if (pending == 0) { manager.flush(); result.success(null) } }
                        for (record in records) {
                            val domain = (record["domain"] as? String ?: "").trimStart('.')
                            if (domain != "neu.edu.cn" && !domain.endsWith(".neu.edu.cn")) { finished(); continue }
                            val expiry = (record["expires"] as? Number)?.toLong()
                            if (expiry != null && expiry <= System.currentTimeMillis()) { finished(); continue }
                            val secure = record["secure"] == true
                            val header = buildString {
                                append("${record["name"]}=${record["value"]}; Path=${record["path"] ?: "/"}")
                                if (record["hostOnly"] != true) append("; Domain=$domain")
                                if (secure) append("; Secure")
                                if (record["httpOnly"] == true) append("; HttpOnly")
                                if (expiry != null) {
                                    val format = SimpleDateFormat("EEE, dd MMM yyyy HH:mm:ss 'GMT'", Locale.US)
                                    format.timeZone = TimeZone.getTimeZone("GMT")
                                    append("; Expires=${format.format(Date(expiry))}")
                                }
                            }
                            manager.setCookie("${if (secure) "https" else "http"}://$domain/", header) { finished() }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
