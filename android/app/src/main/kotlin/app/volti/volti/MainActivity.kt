package app.volti.volti

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var micResult: MethodChannel.Result? = null

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
        // Mikrofon für das Stimmgerät: einmal um Erlaubnis fragen.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "volti/mic").setMethodCallHandler { call, result ->
            if (call.method != "request") {
                result.notImplemented()
            } else if (Build.VERSION.SDK_INT < 23 ||
                checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
                result.success(true)
            } else {
                micResult?.success(false)
                micResult = result
                requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), MIC_REQUEST)
            }
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == MIC_REQUEST) {
            micResult?.success(grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED)
            micResult = null
        }
    }

    companion object {
        private const val MIC_REQUEST = 4711
    }
}
