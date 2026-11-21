package app.volti.volti

import android.Manifest
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedOutputStream
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder

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
        // Audio-Datei in rohe Tondaten umwandeln (für „Spuren trennen“).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "volti/audio").setMethodCallHandler { call, result ->
            if (call.method != "decode") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val input = call.argument<String>("input")!!
            val output = call.argument<String>("output")!!
            val main = Handler(Looper.getMainLooper())
            Thread {
                try {
                    val info = decodeAudio(input, output)
                    main.post { result.success(info) }
                } catch (e: Exception) {
                    main.post { result.error("decode", e.toString(), null) }
                }
            }.start()
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

    /// Wandelt [input] (MP3, M4A/AAC, WAV, FLAC, OGG …) mit den Decodern von
    /// Android in rohe Tondaten um: 32-Bit-Gleitkomma, verschachtelt
    /// (links, rechts …), ohne Kopf. Gibt Abtastrate und Kanäle zurück.
    private fun decodeAudio(input: String, output: String): Map<String, Int> {
        val extractor = MediaExtractor()
        extractor.setDataSource(input)
        var track = -1
        for (i in 0 until extractor.trackCount) {
            val mime = extractor.getTrackFormat(i).getString(MediaFormat.KEY_MIME) ?: ""
            if (mime.startsWith("audio/")) {
                track = i
                break
            }
        }
        if (track < 0) throw IllegalArgumentException("keine Tonspur")
        extractor.selectTrack(track)
        val format = extractor.getTrackFormat(track)
        var rate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        var channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
        val codec = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!)
        codec.configure(format, null, null, 0)
        codec.start()
        var encoding = AudioFormat.ENCODING_PCM_16BIT
        val out = BufferedOutputStream(FileOutputStream(output), 1 shl 20)
        val info = MediaCodec.BufferInfo()
        var inputDone = false
        try {
            while (true) {
                if (!inputDone) {
                    val inIndex = codec.dequeueInputBuffer(10000)
                    if (inIndex >= 0) {
                        val buffer = codec.getInputBuffer(inIndex)!!
                        val size = extractor.readSampleData(buffer, 0)
                        if (size < 0) {
                            codec.queueInputBuffer(inIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            codec.queueInputBuffer(inIndex, 0, size, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }
                val outIndex = codec.dequeueOutputBuffer(info, 10000)
                if (outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    val f = codec.outputFormat
                    rate = f.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    channels = f.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                    if (Build.VERSION.SDK_INT >= 24 && f.containsKey(MediaFormat.KEY_PCM_ENCODING)) {
                        encoding = f.getInteger(MediaFormat.KEY_PCM_ENCODING)
                    }
                } else if (outIndex >= 0) {
                    val buffer = codec.getOutputBuffer(outIndex)!!
                    buffer.position(info.offset)
                    buffer.limit(info.offset + info.size)
                    val data = buffer.slice().order(ByteOrder.nativeOrder())
                    val floats = ByteBuffer.allocate(
                        if (encoding == AudioFormat.ENCODING_PCM_FLOAT) info.size else info.size * 2
                    ).order(ByteOrder.LITTLE_ENDIAN)
                    if (encoding == AudioFormat.ENCODING_PCM_FLOAT) {
                        while (data.remaining() >= 4) floats.putFloat(data.getFloat())
                    } else {
                        while (data.remaining() >= 2) floats.putFloat(data.getShort() / 32768f)
                    }
                    out.write(floats.array(), 0, floats.position())
                    codec.releaseOutputBuffer(outIndex, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
                }
            }
        } finally {
            out.close()
            codec.stop()
            codec.release()
            extractor.release()
        }
        return mapOf("rate" to rate, "channels" to channels)
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
