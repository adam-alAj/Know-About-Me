package com.aj.kam

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.hardware.display.DisplayManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val notificationChannelName = "kam/local_notifications"
    private var pendingNotificationPermissionResult: MethodChannel.Result? = null
    private val methodChannelName = "kam/device_battery"
    private val eventChannelName = "kam/device_battery/events"
    private val networkMethodChannelName = "kam/device_network"
    private val networkEventChannelName = "kam/device_network/events"
    private val activityMethodChannelName = "kam/device_activity"
    private val activityEventChannelName = "kam/device_activity/events"
    private val locationMethodChannelName = "kam/device_location"
    private val locationEventChannelName = "kam/device_location/events"
    private val mapLauncherMethodChannelName = "kam/map_launcher"
    private var batteryReceiver: BroadcastReceiver? = null
    private var screenReceiver: BroadcastReceiver? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var locationListener: LocationListener? = null
    private var pendingLocationPermissionResult: MethodChannel.Result? = null
    private var oneShotListener: LocationListener? = null
    private var oneShotResult: MethodChannel.Result? = null
    private var oneShotFallback: Map<String, Any?>? = null
    private var oneShotFinished = true
    private val mainHandler = Handler(Looper.getMainLooper())
    private val oneShotHandler = Handler(Looper.getMainLooper())
    private val oneShotTimeout = Runnable {
        completeOneShot(oneShotFallback ?: mapOf("error" to "timeout"))
    }

    private companion object {
        const val LOCATION_PERMISSION_REQUEST_CODE = 7401
        const val NOTIFICATION_PERMISSION_REQUEST_CODE = 7402

        // Throttling for the update stream. Foreground-only, battery-aware.
        const val LOCATION_MIN_TIME_MS = 60_000L
        const val LOCATION_MIN_DISTANCE_M = 100f

        // A cached fix younger than this is still handed back as current.
        const val RECENT_FIX_AGE_MS = 60_000L

        // How long a one-shot request waits before falling back.
        const val ONE_SHOT_TIMEOUT_MS = 12_000L
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kam/local_notifications")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "permissionState" -> result.success(notificationPermissionState())
                    "requestPermission" -> {
                        if (Build.VERSION.SDK_INT >= 33 &&
                            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                            val asked = getSharedPreferences("kam_permissions", MODE_PRIVATE)
                                .getBoolean("notification_asked", false)
                            if (asked && !shouldShowRequestPermissionRationale(Manifest.permission.POST_NOTIFICATIONS)) {
                                result.success("denied")
                            } else {
                                getSharedPreferences("kam_permissions", MODE_PRIVATE).edit()
                                    .putBoolean("notification_asked", true).apply()
                                pendingNotificationPermissionResult = result
                                requestPermissions(
                                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                                    NOTIFICATION_PERMISSION_REQUEST_CODE,
                                )
                            }
                        } else result.success(notificationPermissionState())
                    }
                    "show" -> {
                        if (notificationPermissionState() != "granted") {
                            result.error("permission_denied", "Notification permission is not granted.", null)
                        } else {
                            showLocalNotification(call.argument<String>("id") ?: "alert", call.argument<String>("title") ?: "Rule alert", call.argument<String>("body") ?: "", call.argument<String>("payload"))
                            result.success(null)
                        }
                    }
                    "cancelAll" -> {
                        (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).cancelAll()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

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
                                emitEvent(events, readBatteryState(intent))
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
                        override fun onAvailable(network: Network) {
                            val capabilities = manager.getNetworkCapabilities(network)
                            val state = capabilities?.let(::networkState) ?: readNetworkState()
                            mainHandler.post {
                                if (networkCallback === this) {
                                    events.success(state)
                                }
                            }
                        }

                        override fun onCapabilitiesChanged(
                            network: Network,
                            networkCapabilities: NetworkCapabilities,
                        ) {
                            val state = networkState(networkCapabilities)
                            mainHandler.post {
                                if (networkCallback === this) {
                                    events.success(state)
                                }
                            }
                        }

                        override fun onLost(network: Network) {
                            // Allow a default-network handoff to settle before
                            // the one-shot read, avoiding a false offline blip.
                            val lostCallback = this
                            mainHandler.postDelayed({
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

        // Display-state observation. ACTION_SCREEN_ON/OFF are only delivered to
        // dynamically registered receivers while this process is alive; they
        // cannot wake a terminated app, so no background monitoring is claimed.
        // No permission is required for the default Display state or broadcasts.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, activityMethodChannelName)
            .setMethodCallHandler { call, result ->
                if (call.method == "getCurrentActivityState") {
                    result.success(readActivityState())
                } else {
                    result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, activityEventChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    val receiver = object : BroadcastReceiver() {
                        override fun onReceive(context: Context?, intent: Intent?) {
                            when (intent?.action) {
                                Intent.ACTION_SCREEN_ON, Intent.ACTION_SCREEN_OFF ->
                                    emitEvent(events, readActivityState())
                            }
                        }
                    }
                    screenReceiver = receiver
                    val filter = IntentFilter().apply {
                        addAction(Intent.ACTION_SCREEN_ON)
                        addAction(Intent.ACTION_SCREEN_OFF)
                    }
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
                        } else {
                            @Suppress("DEPRECATION")
                            registerReceiver(receiver, filter)
                        }
                    } catch (error: RuntimeException) {
                        screenReceiver = null
                        events.error("screen_monitor_unavailable", error.javaClass.simpleName, null)
                        return
                    }
                    // Start from a real reading, never from an assumed state.
                    emitEvent(events, readActivityState())
                }

                override fun onCancel(arguments: Any?) {
                    unregisterScreenReceiver()
                }
            })

        // Phase 10: location. Foreground only, no background permission and no
        // foreground service. No coordinates are ever logged from here.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, locationMethodChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getLocationStatus" -> result.success(locationStatusMap())
                    "requestLocationPermission" -> requestLocationPermission(result)
                    "getCurrentLocation" -> readCurrentLocation(result)
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, locationEventChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    startLocationUpdates(events)
                }

                override fun onCancel(arguments: Any?) {
                    stopLocationUpdates()
                }
            })

        // Opening an authorized coordinate in an external map application. This
        // is a launch-only bridge: no coordinates are logged, stored, or
        // requested here.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, mapLauncherMethodChannelName)
            .setMethodCallHandler { call, result ->
                if (call.method == "openCoordinates") {
                    val latitude = call.argument<Double>("latitude")
                    val longitude = call.argument<Double>("longitude")
                    if (latitude == null || longitude == null ||
                        latitude < -90.0 || latitude > 90.0 ||
                        longitude < -180.0 || longitude > 180.0) {
                        result.success(false)
                    } else {
                        result.success(
                            openMapLocation(latitude, longitude, call.argument<String>("label")),
                        )
                    }
                } else {
                    result.notImplemented()
                }
            }
    }

    /**
     * Starts whichever application can display a geographic coordinate.
     *
     * A `geo:` URI is the standard deep link; an https Google Maps link is the
     * fallback for a device with no handler for `geo:`. Returns false when
     * neither can be started, so the UI can say so instead of appearing to do
     * nothing.
     */
    private fun openMapLocation(latitude: Double, longitude: Double, label: String?): Boolean {
        val coordinate = "$latitude,$longitude"
        val labelPart = if (label.isNullOrBlank()) "" else "(${Uri.encode(label)})"
        val geoUri = Uri.parse("geo:$coordinate?q=$coordinate$labelPart")
        try {
            startActivity(Intent(Intent.ACTION_VIEW, geoUri))
            return true
        } catch (_: ActivityNotFoundException) {
            // No geo: handler; fall through to the web map fallback.
        }
        val webUri = Uri.parse("https://www.google.com/maps/search/?api=1&query=$coordinate")
        return try {
            startActivity(Intent(Intent.ACTION_VIEW, webUri))
            true
        } catch (_: ActivityNotFoundException) {
            false
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == LOCATION_PERMISSION_REQUEST_CODE) {
            // The user's answer is reflected in the status map; the app must
            // not ask again after a permanent refusal.
            pendingLocationPermissionResult?.success(locationStatusMap())
            pendingLocationPermissionResult = null
        }
        if (requestCode == NOTIFICATION_PERMISSION_REQUEST_CODE) {
            pendingNotificationPermissionResult?.success(notificationPermissionState())
            pendingNotificationPermissionResult = null
        }
    }

    private fun notificationPermissionState(): String {
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            val asked = getSharedPreferences("kam_permissions", MODE_PRIVATE)
                .getBoolean("notification_asked", false)
            return if (asked) "denied" else "notDetermined"
        }
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        return if (manager.areNotificationsEnabled()) "granted" else "denied"
    }

    private fun showLocalNotification(id: String, title: String, body: String, ruleId: String?) {
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(NotificationChannel(notificationChannelName, "Rule alerts", NotificationManager.IMPORTANCE_DEFAULT))
        }
        val intent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            if (ruleId != null) putExtra("ruleId", ruleId)
        }
        val pending = intent?.let { PendingIntent.getActivity(this, id.hashCode(), it, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE) }
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, notificationChannelName) else Notification.Builder(this)
        builder.setSmallIcon(R.drawable.ic_stat_kam).setContentTitle(title).setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body)).setAutoCancel(true).setContentIntent(pending)
        manager.notify(id.hashCode(), builder.build())
    }

    override fun onDestroy() {
        stopNetworkCallback()
        unregisterScreenReceiver()
        stopLocationUpdates()
        cancelOneShot()
        pendingLocationPermissionResult?.error("activity_destroyed", "Location permission request was cancelled.", null)
        pendingLocationPermissionResult = null
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

    private fun locationManager(): LocationManager =
        getSystemService(Context.LOCATION_SERVICE) as LocationManager

    /** Delivers EventChannel values on Flutter's Android UI thread. */
    private fun emitEvent(events: EventChannel.EventSink, value: Any?) {
        mainHandler.post { events.success(value) }
    }

    private fun hasLocationPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        return checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
            checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
    }

    private fun hasPreciseLocationPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        return checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
    }

    private fun isLocationServiceEnabled(): Boolean {
        val manager = locationManager()
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            manager.isLocationEnabled
        } else {
            @Suppress("DEPRECATION")
            manager.isProviderEnabled(LocationManager.GPS_PROVIDER) ||
                @Suppress("DEPRECATION")
                manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
        }
    }

    private fun locationPermissionState(): String {
        val preferences = getSharedPreferences("kam_permissions", MODE_PRIVATE)
        if (hasLocationPermission()) {
            preferences.edit().putBoolean("location_ever_granted", true).apply()
            return "granted"
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return "denied"
        val shouldExplain = shouldShowRequestPermissionRationale(Manifest.permission.ACCESS_FINE_LOCATION) ||
            shouldShowRequestPermissionRationale(Manifest.permission.ACCESS_COARSE_LOCATION)
        if (shouldExplain) return "denied"
        // A one-time grant can expire without an explicit denial. Preserve that
        // distinction so an expired grant is requestable again after restart.
        val wasGranted = preferences.getBoolean("location_ever_granted", false)
        if (wasGranted) return "denied"
        val asked = preferences.getBoolean("location_asked", false)
        return if (asked) "permanentlyDenied" else "notDetermined"
    }

    private fun locationStatusMap(): Map<String, Any?> = mapOf(
        "supported" to true,
        "permission" to locationPermissionState(),
        "precise" to hasPreciseLocationPermission(),
        "serviceEnabled" to isLocationServiceEnabled(),
    )

    private fun requestLocationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M || hasLocationPermission()) {
            result.success(locationStatusMap())
            return
        }
        if (locationPermissionState() == "permanentlyDenied") {
            result.success(locationStatusMap())
            return
        }
        if (pendingLocationPermissionResult != null) {
            result.error("request_in_progress", "A location permission request is already open.", null)
            return
        }
        pendingLocationPermissionResult = result
        getSharedPreferences("kam_permissions", MODE_PRIVATE).edit()
            .putBoolean("location_asked", true)
            .apply()
        requestPermissions(
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION),
            LOCATION_PERMISSION_REQUEST_CODE,
        )
    }

    /**
     * Returns one fix. A cached last-known fix is used only when it is still
     * recent; otherwise a single update is requested with a timeout, after
     * which the cached value (or a timeout reason) is returned. Nothing is
     * invented when no fix is available.
     */
    private fun readCurrentLocation(result: MethodChannel.Result) {
        if (!hasLocationPermission()) {
            result.success(mapOf("error" to "denied"))
            return
        }
        if (!isLocationServiceEnabled()) {
            result.success(mapOf("error" to "disabled"))
            return
        }
        val manager = locationManager()
        val cached = bestLastKnownLocation(manager)
        if (cached != null && System.currentTimeMillis() - cached.time <= RECENT_FIX_AGE_MS) {
            result.success(locationMap(cached))
            return
        }
        val provider = bestProvider(manager)
        if (provider == null) {
            result.success(cached?.let { locationMap(it) } ?: mapOf("error" to "no_fix"))
            return
        }

        oneShotResult = result
        oneShotFinished = false
        oneShotFallback = cached?.let { locationMap(it) }
        val listener = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                completeOneShot(locationMap(location))
            }

            override fun onProviderDisabled(provider: String) {
                completeOneShot(oneShotFallback ?: mapOf("error" to "disabled"))
            }
        }
        oneShotListener = listener
        try {
            manager.requestLocationUpdates(provider, 0L, 0f, listener, Looper.getMainLooper())
        } catch (error: RuntimeException) {
            completeOneShot(oneShotFallback ?: mapOf("error" to "no_fix"))
            return
        }
        oneShotHandler.postDelayed(oneShotTimeout, ONE_SHOT_TIMEOUT_MS)
    }

    /**
     * Completes the one-shot request exactly once. A stale cached fix is
     * returned with its real timestamp (so the app marks it stale) rather than
     * being rewritten to look current.
     */
    private fun completeOneShot(value: Any?) {
        if (oneShotFinished) return
        oneShotFinished = true
        oneShotHandler.removeCallbacks(oneShotTimeout)
        oneShotListener?.let { listener ->
            try {
                locationManager().removeUpdates(listener)
            } catch (_: IllegalArgumentException) {
                // The provider may already be gone.
            }
        }
        oneShotListener = null
        val result = oneShotResult
        oneShotResult = null
        result?.success(value)
    }

    private fun cancelOneShot() {
        oneShotFinished = true
        oneShotHandler.removeCallbacks(oneShotTimeout)
        oneShotListener?.let { listener ->
            try {
                locationManager().removeUpdates(listener)
            } catch (_: IllegalArgumentException) {
                // Already released.
            }
        }
        oneShotListener = null
        oneShotResult = null
    }

    private fun startLocationUpdates(events: EventChannel.EventSink) {
        if (!hasLocationPermission()) {
            events.error("location_permission_missing", "Location permission is not granted.", null)
            return
        }
        if (!isLocationServiceEnabled()) {
            events.error("location_service_disabled", "Location services are disabled.", null)
            return
        }
        val manager = locationManager()
        val provider = bestProvider(manager)
        if (provider == null) {
            events.error("location_provider_unavailable", "No location provider is enabled.", null)
            return
        }
        stopLocationUpdates()
        val listener = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                emitEvent(events, locationMap(location))
            }

            override fun onProviderDisabled(provider: String) {
                events.error("location_service_disabled", "Location services were disabled.", null)
            }
        }
        locationListener = listener
        try {
            manager.requestLocationUpdates(
                provider,
                LOCATION_MIN_TIME_MS,
                LOCATION_MIN_DISTANCE_M,
                listener,
                Looper.getMainLooper(),
            )
        } catch (error: RuntimeException) {
            locationListener = null
            events.error("location_updates_failed", error.javaClass.simpleName, null)
        }
    }

    private fun stopLocationUpdates() {
        val listener = locationListener
        locationListener = null
        if (listener != null) {
            try {
                locationManager().removeUpdates(listener)
            } catch (_: IllegalArgumentException) {
                // Already released.
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun bestProvider(manager: LocationManager): String? {
        for (candidate in listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)) {
            if (manager.isProviderEnabled(candidate)) {
                try {
                    if (manager.getProvider(candidate) != null) return candidate
                } catch (_: IllegalArgumentException) {
                    // Provider not present on this device.
                }
            }
        }
        return null
    }

    @Suppress("DEPRECATION")
    private fun bestLastKnownLocation(manager: LocationManager): Location? {
        val candidates = listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)
            .mapNotNull { provider ->
                try {
                    if (manager.isProviderEnabled(provider)) manager.getLastKnownLocation(provider) else null
                } catch (_: IllegalArgumentException) {
                    null
                }
            }
        return candidates.maxByOrNull { it.time }
    }

    private fun locationMap(location: Location): Map<String, Any?> = mapOf(
        "latitude" to location.latitude,
        "longitude" to location.longitude,
        "accuracyMeters" to if (location.hasAccuracy()) location.accuracy.toDouble() else null,
        "observedAt" to isoUtc(location.time),
        // Reduced accuracy is what the OS actually granted, never inferred.
        "approximate" to !hasPreciseLocationPermission(),
    )

    private fun isoUtc(millis: Long): String {
        val format = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
        format.timeZone = TimeZone.getTimeZone("UTC")
        return format.format(Date(millis))
    }

    private fun unregisterScreenReceiver() {
        screenReceiver?.let { receiver ->
            try {
                unregisterReceiver(receiver)
            } catch (_: IllegalArgumentException) {
                // The stream or activity may already have released it.
            }
        }
        screenReceiver = null
    }

    private fun readActivityState(): Map<String, Any?> {
        return try {
            val displays = getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
            val display = displays.getDisplay(android.view.Display.DEFAULT_DISPLAY)
                ?: return mapOf("screenState" to null, "screenStateSupported" to true)
            val state = when (display.state) {
                android.view.Display.STATE_ON -> "on"
                android.view.Display.STATE_OFF -> "off"
                else -> null
            }
            mapOf("screenState" to state, "screenStateSupported" to true)
        } catch (error: RuntimeException) {
            // Report no value rather than guessing the display state.
            mapOf(
                "screenState" to null,
                "screenStateSupported" to true,
            )
        }
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
