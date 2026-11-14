package app.volti.volti

import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Bildschirm wach halten, solange Noten offen sind.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "volti/screen").setMethodCallHandler { call, result ->
            if (call.method == "keepAwake") {
                if (call.arguments == true) {
                    window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                } else {
                    window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                }
                result.success(true)
            } else {
                result.notImplemented()
            }
        }
    }
}
