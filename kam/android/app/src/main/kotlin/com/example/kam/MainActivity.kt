package com.example.kam

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val methodChannelName = "kam/device_battery"
    private val eventChannelName = "kam/device_battery/events"
    private var batteryReceiver: BroadcastReceiver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName)
            .setMethodCallHandler { call, result ->
                if (call.method == "getCurrentBatteryState") {
                    result.success(readBatteryState())
                } else {
                    result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    val receiver = object : BroadcastReceiver() {
                        override fun onReceive(context: Context?, intent: Intent?) {
                            if (intent?.action == Intent.ACTION_BATTERY_CHANGED) {
                                events.success(readBatteryState(intent))
                            }
                        }
                    }
                    batteryReceiver = receiver
                    val filter = IntentFilter(Intent.ACTION_BATTERY_CHANGED)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
                    } else {
                        @Suppress("DEPRECATION")
                        registerReceiver(receiver, filter)
                    }
                }

                override fun onCancel(arguments: Any?) {
                    batteryReceiver?.let { receiver ->
                        try {
                            unregisterReceiver(receiver)
                        } catch (_: IllegalArgumentException) {
                            // The receiver may already have been detached.
                        }
                    }
                    batteryReceiver = null
                }
            })
    }

    override fun onDestroy() {
        batteryReceiver?.let { receiver ->
            try {
                unregisterReceiver(receiver)
            } catch (_: IllegalArgumentException) {
                // The event stream may already have cancelled it.
            }
        }
        batteryReceiver = null
        super.onDestroy()
    }

    private fun readBatteryState(
        stickyIntent: Intent? = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED)),
    ): Map<String, Any?> {
        if (stickyIntent == null || stickyIntent.getBooleanExtra(BatteryManager.EXTRA_PRESENT, true).not()) {
            return mapOf(
                "percentage" to null,
                "chargingState" to "unknown",
                "chargingSource" to null,
                "chargingSourceSupported" to true,
            )
        }

        val level = stickyIntent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
        val scale = stickyIntent.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
        val percentage = if (level >= 0 && scale > 0) {
            ((level * 100f) / scale).toInt()
        } else {
            null
        }

        val status = when (stickyIntent.getIntExtra(BatteryManager.EXTRA_STATUS, -1)) {
            BatteryManager.BATTERY_STATUS_CHARGING -> "charging"
            BatteryManager.BATTERY_STATUS_FULL -> "full"
            BatteryManager.BATTERY_STATUS_DISCHARGING -> "discharging"
            BatteryManager.BATTERY_STATUS_NOT_CHARGING -> "notCharging"
            else -> "unknown"
        }
        val source = when (stickyIntent.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0)) {
            BatteryManager.BATTERY_PLUGGED_USB -> "usb"
            BatteryManager.BATTERY_PLUGGED_AC -> "ac"
            BatteryManager.BATTERY_PLUGGED_WIRELESS -> "wireless"
            else -> "unknown"
        }

        return mapOf(
            "percentage" to percentage,
            "chargingState" to status,
            "chargingSource" to source,
            "chargingSourceSupported" to true,
        )
    }
}
