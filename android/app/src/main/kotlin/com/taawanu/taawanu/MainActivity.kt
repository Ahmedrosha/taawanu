package com.taawanu.taawanu

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // التطبيق بيكتب بيانات الويدجتس وبعدين يطلب تحديثها.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "taawanu/widgets").setMethodCallHandler { call, result ->
            if (call.method == "update") {
                try {
                    Widgets.updateAll(applicationContext)
                } catch (e: Exception) {
                    // الويدجتس مش أساسية.
                }
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }
}
