package com.vitor.pavimenta_ai_mobile

import android.Manifest
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CAMERA_DIAGNOSTIC_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                IS_CAMERA_PERMISSION_PERMANENTLY_DENIED ->
                    result.success(isCameraPermissionPermanentlyDenied())
                else -> result.notImplemented()
            }
        }
    }

    private fun isCameraPermissionPermanentlyDenied(): Boolean {
        val isDenied = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.CAMERA,
        ) != PackageManager.PERMISSION_GRANTED
        val canExplainDenial = ActivityCompat.shouldShowRequestPermissionRationale(
            this,
            Manifest.permission.CAMERA,
        )

        return isDenied && !canExplainDenial
    }

    private companion object {
        const val CAMERA_DIAGNOSTIC_CHANNEL =
            "com.vitor.pavimenta_ai_mobile/e0_camera_diagnostic"
        const val IS_CAMERA_PERMISSION_PERMANENTLY_DENIED =
            "isCameraPermissionPermanentlyDenied"
    }
}
