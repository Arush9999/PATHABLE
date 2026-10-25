package com.pathable.pathable

import android.Manifest
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {
    private lateinit var speechBridge: GoogleSpeechBridge

    private val compassChannel = "pathable/compass"
    private var sensorManager: SensorManager? = null
    private var headingSink: EventChannel.EventSink? = null
    private var wantCompass = false
    private var registered = false
    private val rotationMatrix = FloatArray(9)
    private val orientation = FloatArray(3)

    private val listener = object : SensorEventListener {
        override fun onSensorChanged(event: SensorEvent) {
            if (event.sensor.type != Sensor.TYPE_ROTATION_VECTOR) return
            val values = event.values.clone()
            runOnUiThread {
                val sink = headingSink ?: return@runOnUiThread
                try {
                    SensorManager.getRotationMatrixFromVector(rotationMatrix, values)
                    SensorManager.getOrientation(rotationMatrix, orientation)
                    var degrees = Math.toDegrees(orientation[0].toDouble())
                    if (degrees < 0) degrees += 360.0
                    sink.success(degrees)
                } catch (_: Exception) {
                    // A bad sample must not close the stream or drop the arrow.
                }
            }
        }

        override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if (!::speechBridge.isInitialized) {
            speechBridge = GoogleSpeechBridge(this) {
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(Manifest.permission.RECORD_AUDIO),
                    recordAudioRequestCode,
                )
            }
        }
        speechBridge.attach(flutterEngine.dartExecutor.binaryMessenger)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, compassChannel)
            .setStreamHandler(
                object : EventChannel.StreamHandler {
                    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                        headingSink = events
                        wantCompass = true
                        registerCompass()
                    }

                    override fun onCancel(arguments: Any?) {
                        wantCompass = false
                        unregisterCompass()
                        headingSink = null
                    }
                },
            )
    }

    override fun onPause() {
        unregisterCompass()
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
        if (wantCompass) registerCompass()
    }

    override fun onDestroy() {
        if (::speechBridge.isInitialized) {
            speechBridge.dispose()
        }
        super.onDestroy()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != recordAudioRequestCode || !::speechBridge.isInitialized) return
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        speechBridge.onRecordAudioPermission(granted)
    }

    companion object {
        private const val recordAudioRequestCode = 48120
    }

    private fun registerCompass() {
        if (registered || !wantCompass) return
        val manager = getSystemService(SENSOR_SERVICE) as SensorManager
        sensorManager = manager
        val sensor = manager.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR) ?: return
        registered = manager.registerListener(
            listener,
            sensor,
            SensorManager.SENSOR_DELAY_NORMAL,
        )
    }

    private fun unregisterCompass() {
        sensorManager?.unregisterListener(listener)
        registered = false
    }
}
