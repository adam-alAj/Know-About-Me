package com.example.kam

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val methodChannelName = "kam/device_battery"
    private val eventChannelName = "kam/device_battery/events"
    private val networkMethodChannelName = "kam/device_network"
    private val networkEventChannelName = "kam/device_network/events"
    private var batteryReceiver: BroadcastReceiver? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null

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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, networkMethodChannelName)
            .setMethodCallHandler { call, result ->
                if (call.method == "getCurrentNetworkState") {
                    result.success(readNetworkState())
                } else {
                    result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, networkEventChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    val manager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                    val callback = object : ConnectivityManager.NetworkCallback() {
                        override fun onCapabilitiesChanged(
                            network: Network,
                            networkCapabilities: NetworkCapabilities,
                        ) {
                            events.success(networkState(networkCapabilities))
                        }

                        override fun onLost(network: Network) {
                            // Allow a default-network handoff to settle before
                            // the one-shot read, avoiding a false offline blip.
                            val lostCallback = this
                            Handler(Looper.getMainLooper()).postDelayed({
                                if (networkCallback === lostCallback) {
                                    events.success(readNetworkState())
                                }
                            }, 500)
                        }
                    }
                    networkCallback = callback
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                            manager.registerDefaultNetworkCallback(callback)
                        } else {
                            @Suppress("DEPRECATION")
                            manager.registerNetworkCallback(
                                NetworkRequest.Builder()
                                    .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                                    .build(),
                                callback,
                            )
                        }
                    } catch (error: RuntimeException) {
                        networkCallback = null
                        events.error("network_monitor_unavailable", error.javaClass.simpleName, null)
                    }
                }

                override fun onCancel(arguments: Any?) {
                    stopNetworkCallback()
                }
            })
    }

    override fun onDestroy() {
        stopNetworkCallback()
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

    private fun stopNetworkCallback() {
        networkCallback?.let { callback ->
            val manager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            try {
                manager.unregisterNetworkCallback(callback)
            } catch (_: IllegalArgumentException) {
                // The stream or activity may already have released it.
            }
        }
        networkCallback = null
    }

    private fun readNetworkState(): Map<String, String> {
        val manager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            @Suppress("DEPRECATION")
            val legacy = manager.activeNetworkInfo ?: return networkState(null)
            val type = when (legacy.type) {
                ConnectivityManager.TYPE_WIFI -> "wifi"
                ConnectivityManager.TYPE_MOBILE -> "mobile"
                ConnectivityManager.TYPE_ETHERNET -> "ethernet"
                else -> "unknown"
            }
            return mapOf(
                "connectivityType" to type,
                // Pre-Marshmallow APIs do not expose system validation.
                "internetReachability" to "unknown",
                "onlineStatus" to if (legacy.isConnected) "online" else "offline",
            )
        }
        val network = manager.activeNetwork ?: return networkState(null)
        val capabilities = manager.getNetworkCapabilities(network)
            ?: return mapOf(
                "connectivityType" to "unknown",
                "internetReachability" to "unknown",
                "onlineStatus" to "unknown",
            )
        return networkState(capabilities)
    }

    private fun networkState(capabilities: NetworkCapabilities?): Map<String, String> {
        if (capabilities == null) {
            return mapOf(
                "connectivityType" to "none",
                "internetReachability" to "unavailable",
                "onlineStatus" to "offline",
            )
        }

        val type = when {
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN) -> "vpn"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "mobile"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_BLUETOOTH) -> "bluetooth"
            else -> "unknown"
        }
        val validated = capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
        return mapOf(
            "connectivityType" to type,
            "internetReachability" to if (validated) "available" else "unavailable",
            "onlineStatus" to if (validated) "online" else "offline",
        )
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
