package com.aj.kam.background_monitoring

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.app.ActivityManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.BatteryManager
import android.os.PowerManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Small application plugin so the same Android APIs are available to the
 * Workmanager-created FlutterEngine after the Activity has been destroyed.
 * It never reads location or user-activity history.
 */
class BackgroundDeviceStatePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var appContext: Context
    private var channel: MethodChannel? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "collectSupportedState") {
            result.notImplemented()
            return
        }
        try {
            result.success(collectSupportedState())
        } catch (error: SecurityException) {
            result.error("state_permission_denied", "Android denied a supported state read.", null)
        } catch (error: RuntimeException) {
            result.error("state_read_failed", "Android could not read supported device state.", null)
        }
    }

    private fun collectSupportedState(): Map<String, Any?> {
        val batteryIntent = appContext.registerReceiver(
            null,
            IntentFilter(Intent.ACTION_BATTERY_CHANGED),
        )
        val level = batteryIntent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = batteryIntent?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        val percentage = if (level >= 0 && scale > 0) (level * 100f / scale).toInt() else null
        val chargingState = when (
            batteryIntent?.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
        ) {
            BatteryManager.BATTERY_STATUS_CHARGING -> "charging"
            BatteryManager.BATTERY_STATUS_FULL -> "full"
            BatteryManager.BATTERY_STATUS_DISCHARGING -> "discharging"
            BatteryManager.BATTERY_STATUS_NOT_CHARGING -> "notCharging"
            else -> "unknown"
        }
        val chargingSource = when (
            batteryIntent?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0)
        ) {
            BatteryManager.BATTERY_PLUGGED_USB -> "usb"
            BatteryManager.BATTERY_PLUGGED_AC -> "ac"
            BatteryManager.BATTERY_PLUGGED_WIRELESS -> "wireless"
            else -> "unknown"
        }

        val connectivity = appContext.getSystemService(Context.CONNECTIVITY_SERVICE)
            as ConnectivityManager
        val network = connectivity.activeNetwork
        val capabilities = network?.let(connectivity::getNetworkCapabilities)
        val transport = when {
            capabilities == null -> "none"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN) -> "vpn"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "mobile"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_BLUETOOTH) -> "bluetooth"
            else -> "unknown"
        }
        val validated = capabilities?.hasCapability(
            NetworkCapabilities.NET_CAPABILITY_VALIDATED,
        ) == true
        val onlineStatus = if (validated) "online" else if (capabilities == null) "offline" else "offline"
        val interactive = (appContext.getSystemService(Context.POWER_SERVICE) as PowerManager)
            .isInteractive
        val processInfo = ActivityManager.RunningAppProcessInfo()
        ActivityManager.getMyMemoryState(processInfo)
        val appVisible = processInfo.importance <=
            ActivityManager.RunningAppProcessInfo.IMPORTANCE_VISIBLE
        val observedAt = System.currentTimeMillis()

        return mapOf(
            "observedAtEpochMillis" to observedAt,
            "batteryPercentage" to percentage,
            "chargingState" to chargingState,
            "chargingSource" to chargingSource,
            "connectivityType" to transport,
            "internetReachability" to if (capabilities == null) "unavailable" else if (validated) "available" else "unavailable",
            "networkStatus" to if (validated) "online" else "offline",
            "screenState" to if (interactive) "on" else "off",
            "appVisible" to appVisible,
        )
    }

    private companion object {
        const val CHANNEL = "kam/background_device_state"
    }
}
