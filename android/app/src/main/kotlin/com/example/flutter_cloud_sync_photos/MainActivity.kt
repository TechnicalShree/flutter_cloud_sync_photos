package com.example.flutter_cloud_sync_photos

import android.content.Context
import android.telephony.TelephonyManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
  private val channelName = "flutter_cloud_sync_photos/networkState"

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)

    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
      .setMethodCallHandler { call, result ->
        when (call.method) {
          "isRoaming" -> result.success(checkIsRoaming())
          else -> result.notImplemented()
        }
      }
  }

  private fun checkIsRoaming(): Boolean? {
    val telephonyManager =
      getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager ?: return null

    return try {
      telephonyManager.isNetworkRoaming
    } catch (_: SecurityException) {
      null
    }
  }
}
