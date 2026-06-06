package xyz.infinica.dekon

import android.Manifest
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.IOException
import java.util.ArrayDeque

class MainActivity : FlutterActivity() {
    private var pendingBackupSave: PendingBackupSave? = null
    private var syncRegistrationListener: NsdManager.RegistrationListener? = null
    private var syncRegistration: SyncServiceRegistration? = null
    private var syncRegistrationInProgress = false
    private var pendingNetworkReregister = false
    private var syncNetworkCallback: ConnectivityManager.NetworkCallback? = null
    private var syncNetworkReregister: Runnable? = null
    private var syncDiscoverySession: SyncDiscoverySession? = null
    private var pendingNearbyWifiPermission: PendingNearbyWifiPermission? = null
    private var multicastLock: WifiManager.MulticastLock? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val networkHandler = Handler(Looper.getMainLooper())

    override fun onCreate(savedInstanceState: Bundle?) {
        initializeMlKitIfAvailable()
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BACKUP_FILES_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "saveBackupFile" -> saveBackupFile(call, result)
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            APP_ACTIONS_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "openUrl" -> openUrl(call, result)
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SYNC_DISCOVERY_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "registerMainService" -> registerMainService(call, result)
                "unregisterMainService" -> unregisterMainService(result)
                "discoverMainServices" -> discoverMainServices(call, result)
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        stopActiveDiscovery()
        unregisterRegisteredSyncService()
        super.onDestroy()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == SAVE_BACKUP_REQUEST_CODE) {
            handleBackupSaveResult(resultCode, data)
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (requestCode != NEARBY_WIFI_PERMISSION_REQUEST_CODE) {
            super.onRequestPermissionsResult(requestCode, permissions, grantResults)
            return
        }
        val pending = pendingNearbyWifiPermission ?: return
        pendingNearbyWifiPermission = null
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        if (!granted) {
            pending.result.error(
                "nearby_wifi_permission_denied",
                "Nearby Wi-Fi permission is required for sync discovery.",
                null,
            )
            return
        }
        try {
            pending.onGranted()
        } catch (error: Exception) {
            pending.result.error("sync_discovery_failed", "Sync discovery failed.", null)
        }
    }

    private fun saveBackupFile(call: MethodCall, result: MethodChannel.Result) {
        if (pendingBackupSave != null) {
            result.error("save_in_progress", "A backup save is already in progress.", null)
            return
        }

        val sourcePath = call.argument<String>("sourcePath")
        val fileName = call.argument<String>("fileName")
        val mimeType = call.argument<String>("mimeType") ?: "application/json"
        if (sourcePath.isNullOrBlank() || fileName.isNullOrBlank()) {
            result.error("invalid_arguments", "Backup save arguments are missing.", null)
            return
        }
        if (!File(sourcePath).isFile) {
            result.error("invalid_source", "Backup file is missing.", null)
            return
        }

        pendingBackupSave = PendingBackupSave(
            sourcePath = sourcePath,
            fileName = fileName,
            result = result,
        )

        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = mimeType
            putExtra(Intent.EXTRA_TITLE, fileName)
            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        }
        try {
            startActivityForResult(intent, SAVE_BACKUP_REQUEST_CODE)
        } catch (error: Exception) {
            pendingBackupSave = null
            result.error("storage_access_denied", "Could not open backup save location.", null)
        }
    }

    private fun handleBackupSaveResult(resultCode: Int, data: Intent?) {
        val save = pendingBackupSave ?: return
        pendingBackupSave = null

        if (resultCode != Activity.RESULT_OK) {
            save.result.success(null)
            return
        }

        val uri: Uri? = data?.data
        if (uri == null) {
            save.result.error("storage_access_denied", "Backup save location was unavailable.", null)
            return
        }

        try {
            contentResolver.openOutputStream(uri, "wt")?.use { output ->
                FileInputStream(save.sourcePath).use { input ->
                    input.copyTo(output)
                }
            } ?: throw IOException("Could not open backup save location.")
            save.result.success(mapOf("uri" to uri.toString(), "fileName" to save.fileName))
        } catch (error: SecurityException) {
            save.result.error("storage_access_denied", "Storage access was denied.", null)
        } catch (error: IOException) {
            save.result.error("storage_access_denied", "Backup could not be written.", null)
        }
    }

    private fun openUrl(call: MethodCall, result: MethodChannel.Result) {
        val url = call.argument<String>("url")
        if (url.isNullOrBlank()) {
            result.error("invalid_arguments", "URL is missing.", null)
            return
        }

        val uri = Uri.parse(url)
        if (uri.scheme != "https") {
            result.error("unsupported_url", "Only HTTPS links can be opened.", null)
            return
        }

        try {
            startActivity(Intent(Intent.ACTION_VIEW, uri))
            result.success(null)
        } catch (error: ActivityNotFoundException) {
            result.error("no_handler", "No app is available to open this link.", null)
        }
    }

    private fun registerMainService(call: MethodCall, result: MethodChannel.Result) {
        val deviceId = call.argument<String>("deviceId")
        val port = call.argument<Int>("port")
        val protocolVersion = call.argument<Int>("protocolVersion")
        if (deviceId.isNullOrBlank() || port == null || port <= 0 || protocolVersion == null) {
            result.error("invalid_arguments", "Sync discovery arguments are missing.", null)
            return
        }
        if (!ensureNearbyWifiPermission(result) { registerMainService(call, result) }) return
        if (nsdManager() == null) {
            result.error("nsd_unavailable", "Network service discovery is unavailable.", null)
            return
        }

        val registration = SyncServiceRegistration(
            deviceId = deviceId,
            port = port,
            protocolVersion = protocolVersion,
        )
        syncRegistration = registration
        registerSyncService(registration, result)
    }

    private fun registerSyncService(
        registration: SyncServiceRegistration,
        result: MethodChannel.Result?,
    ) {
        val manager = nsdManager()
        if (manager == null) {
            result?.error("nsd_unavailable", "Network service discovery is unavailable.", null)
            return
        }
        if (syncRegistrationInProgress) {
            if (result == null) {
                pendingNetworkReregister = true
            } else {
                result.error(
                    "registration_in_progress",
                    "Sync service registration is already running.",
                    null,
                )
            }
            return
        }

        syncRegistrationInProgress = true
        unregisterRegisteredSyncService(clearDesiredRegistration = false)
        acquireMulticastLock()

        val listener = object : NsdManager.RegistrationListener {
            private var completed = false

            override fun onServiceRegistered(serviceInfo: NsdServiceInfo) {
                if (completed) return
                completed = true
                Log.i(TAG, "Sync service registered as ${serviceInfo.serviceName}.")
                finishSyncRegistrationAttempt()
                ensureNetworkCallbackRegistered()
                result?.success(null)
            }

            override fun onRegistrationFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                if (completed) return
                completed = true
                syncRegistrationListener = null
                releaseMulticastLockIfIdle()
                finishSyncRegistrationAttempt()
                if (result == null) {
                    Log.w(TAG, "Sync service registration failed after network change: $errorCode")
                } else {
                    result.error(
                        "registration_failed",
                        "Sync service registration failed: $errorCode.",
                        null,
                    )
                }
            }

            override fun onServiceUnregistered(serviceInfo: NsdServiceInfo) {}

            override fun onUnregistrationFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                Log.w(TAG, "Sync service unregistration failed: $errorCode")
            }
        }

        val serviceInfo = NsdServiceInfo().apply {
            serviceName = "Dekon-${registration.deviceId.takeLast(12)}"
            serviceType = DEKON_SYNC_SERVICE_TYPE
            this.port = registration.port
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                network = null
            }
            setAttribute("device_id", registration.deviceId)
            setAttribute("protocol_version", registration.protocolVersion.toString())
        }

        syncRegistrationListener = listener
        try {
            manager.registerService(serviceInfo, NsdManager.PROTOCOL_DNS_SD, listener)
        } catch (error: Exception) {
            syncRegistrationListener = null
            releaseMulticastLockIfIdle()
            finishSyncRegistrationAttempt()
            if (result == null) {
                Log.w(TAG, "Sync service registration failed after network change.", error)
            } else {
                result.error("registration_failed", "Sync service registration failed.", null)
            }
        }
    }

    private fun unregisterMainService(result: MethodChannel.Result) {
        unregisterRegisteredSyncService()
        result.success(null)
    }

    private fun discoverMainServices(call: MethodCall, result: MethodChannel.Result) {
        if (!ensureNearbyWifiPermission(result) { discoverMainServices(call, result) }) return
        val manager = nsdManager()
        if (manager == null) {
            result.error("nsd_unavailable", "Network service discovery is unavailable.", null)
            return
        }
        if (syncDiscoverySession != null) {
            result.error("discovery_in_progress", "Sync discovery is already running.", null)
            return
        }
        val timeoutMillis = (
            call.argument<Int>("timeoutMillis") ?: DEFAULT_DISCOVERY_TIMEOUT_MILLIS
        ).coerceIn(500, MAX_DISCOVERY_TIMEOUT_MILLIS)
        acquireMulticastLock()
        val session = SyncDiscoverySession(manager, result)
        syncDiscoverySession = session
        session.start(timeoutMillis.toLong())
    }

    private fun ensureNearbyWifiPermission(
        result: MethodChannel.Result,
        onGranted: () -> Unit,
    ): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        if (
            checkSelfPermission(Manifest.permission.NEARBY_WIFI_DEVICES) ==
                PackageManager.PERMISSION_GRANTED
        ) {
            return true
        }
        if (pendingNearbyWifiPermission != null) {
            result.error(
                "nearby_wifi_permission_pending",
                "Nearby Wi-Fi permission is already being requested.",
                null,
            )
            return false
        }
        pendingNearbyWifiPermission = PendingNearbyWifiPermission(result, onGranted)
        requestPermissions(
            arrayOf(Manifest.permission.NEARBY_WIFI_DEVICES),
            NEARBY_WIFI_PERMISSION_REQUEST_CODE,
        )
        return false
    }

    private fun unregisterRegisteredSyncService(clearDesiredRegistration: Boolean = true) {
        if (clearDesiredRegistration) {
            syncRegistration = null
            pendingNetworkReregister = false
            syncRegistrationInProgress = false
            unregisterNetworkCallback()
        }
        val listener = syncRegistrationListener ?: return
        syncRegistrationListener = null
        try {
            nsdManager()?.unregisterService(listener)
        } catch (error: Exception) {
            Log.w(TAG, "Could not unregister sync service.", error)
        } finally {
            releaseMulticastLockIfIdle()
        }
    }

    private fun finishSyncRegistrationAttempt() {
        syncRegistrationInProgress = false
        if (!pendingNetworkReregister) return
        pendingNetworkReregister = false
        scheduleSyncServiceReregister("pending_network_change")
    }

    private fun ensureNetworkCallbackRegistered() {
        if (syncNetworkCallback != null || syncRegistration == null) return
        val manager = connectivityManager() ?: return
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                if (isLocalNetwork(network)) {
                    scheduleSyncServiceReregister("network_available")
                }
            }

            override fun onCapabilitiesChanged(
                network: Network,
                networkCapabilities: NetworkCapabilities,
            ) {
                if (isLocalNetwork(networkCapabilities)) {
                    scheduleSyncServiceReregister("network_capabilities_changed")
                }
            }

            override fun onLost(network: Network) {
                scheduleSyncServiceReregister("network_lost")
            }
        }
        try {
            manager.registerDefaultNetworkCallback(callback)
            syncNetworkCallback = callback
        } catch (error: Exception) {
            Log.w(TAG, "Could not watch network changes for sync discovery.", error)
        }
    }

    private fun unregisterNetworkCallback() {
        val callback = syncNetworkCallback ?: return
        syncNetworkCallback = null
        syncNetworkReregister?.let { networkHandler.removeCallbacks(it) }
        syncNetworkReregister = null
        try {
            connectivityManager()?.unregisterNetworkCallback(callback)
        } catch (error: Exception) {
            Log.w(TAG, "Could not stop watching network changes for sync discovery.", error)
        }
    }

    private fun scheduleSyncServiceReregister(reason: String) {
        networkHandler.post {
            if (syncRegistration == null) return@post
            if (syncRegistrationInProgress) {
                pendingNetworkReregister = true
                return@post
            }
            syncNetworkReregister?.let { networkHandler.removeCallbacks(it) }
            val task = Runnable {
                syncNetworkReregister = null
                reregisterSyncService(reason)
            }
            syncNetworkReregister = task
            networkHandler.postDelayed(task, NETWORK_REREGISTER_DELAY_MILLIS)
        }
    }

    private fun reregisterSyncService(reason: String) {
        val registration = syncRegistration ?: return
        Log.i(TAG, "Refreshing sync service registration after $reason.")
        registerSyncService(registration, null)
    }

    private fun stopActiveDiscovery() {
        syncDiscoverySession?.finishSuccess()
    }

    private fun nsdManager(): NsdManager? {
        return getSystemService(Context.NSD_SERVICE) as? NsdManager
    }

    private fun connectivityManager(): ConnectivityManager? {
        return getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
    }

    private fun isLocalNetwork(network: Network): Boolean {
        val capabilities = connectivityManager()?.getNetworkCapabilities(network) ?: return true
        return isLocalNetwork(capabilities)
    }

    private fun isLocalNetwork(capabilities: NetworkCapabilities): Boolean {
        return capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)
    }

    private fun acquireMulticastLock() {
        if (multicastLock?.isHeld == true) return
        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
        multicastLock = wifi?.createMulticastLock("dekon-sync-discovery")?.apply {
            setReferenceCounted(false)
            try {
                acquire()
            } catch (error: SecurityException) {
                Log.w(TAG, "Could not acquire multicast lock.", error)
            }
        }
    }

    private fun releaseMulticastLockIfIdle() {
        if (syncRegistrationListener != null || syncDiscoverySession != null) return
        val lock = multicastLock
        multicastLock = null
        if (lock?.isHeld == true) {
            try {
                lock.release()
            } catch (error: RuntimeException) {
                Log.w(TAG, "Could not release multicast lock.", error)
            }
        }
    }

    private fun isDekonSyncServiceType(serviceType: String?): Boolean {
        val normalized = serviceType?.trimEnd('.') ?: return false
        val expected = DEKON_SYNC_SERVICE_TYPE.trimEnd('.')
        return normalized.equals(expected, ignoreCase = true) ||
            normalized.startsWith("$expected.", ignoreCase = true)
    }

    private fun NsdServiceInfo.toDiscoveryMap(): Map<String, Any>? {
        if (!isDekonSyncServiceType(serviceType)) return null
        val hostAddress = host?.hostAddress ?: return null
        val deviceId = attributes["device_id"]?.toString(Charsets.UTF_8).orEmpty()
        val protocolVersion = attributes["protocol_version"]
            ?.toString(Charsets.UTF_8)
            ?.toIntOrNull()
            ?: 0
        if (port <= 0) return null
        return mapOf(
            "serviceName" to serviceName,
            "host" to hostAddress,
            "port" to port,
            "deviceId" to deviceId,
            "protocolVersion" to protocolVersion,
        )
    }

    private inner class SyncDiscoverySession(
        private val manager: NsdManager,
        private val result: MethodChannel.Result,
    ) {
        private val results = mutableListOf<Map<String, Any>>()
        private val pending = ArrayDeque<NsdServiceInfo>()
        private var resolving = false
        private var finished = false

        private val discoveryListener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(serviceType: String) {
                Log.i(TAG, "Sync discovery started for $serviceType.")
            }

            override fun onServiceFound(serviceInfo: NsdServiceInfo) {
                if (finished) return
                if (!isDekonSyncServiceType(serviceInfo.serviceType)) return
                Log.i(
                    TAG,
                    "Sync service found: ${serviceInfo.serviceName} ${serviceInfo.serviceType}.",
                )
                pending.add(serviceInfo)
                resolveNext()
            }

            override fun onServiceLost(serviceInfo: NsdServiceInfo) {}

            override fun onDiscoveryStopped(serviceType: String) {}

            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
                finishError("discovery_failed", "Sync discovery failed: $errorCode.")
            }

            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {
                Log.w(TAG, "Sync discovery stop failed: $errorCode")
            }
        }

        fun start(timeoutMillis: Long) {
            mainHandler.postDelayed({ finishSuccess() }, timeoutMillis)
            try {
                manager.discoverServices(
                    DEKON_SYNC_SERVICE_TYPE,
                    NsdManager.PROTOCOL_DNS_SD,
                    discoveryListener,
                )
            } catch (error: Exception) {
                finishError("discovery_failed", "Sync discovery failed.")
            }
        }

        fun finishSuccess() {
            if (finished) return
            finished = true
            mainHandler.removeCallbacksAndMessages(null)
            try {
                manager.stopServiceDiscovery(discoveryListener)
            } catch (error: Exception) {
                Log.w(TAG, "Could not stop sync discovery.", error)
            }
            if (syncDiscoverySession === this) {
                syncDiscoverySession = null
            }
            releaseMulticastLockIfIdle()
            Log.i(TAG, "Sync discovery finished with ${results.size} resolved result(s).")
            result.success(results)
        }

        private fun finishError(code: String, message: String) {
            if (finished) return
            finished = true
            mainHandler.removeCallbacksAndMessages(null)
            try {
                manager.stopServiceDiscovery(discoveryListener)
            } catch (error: Exception) {
                Log.w(TAG, "Could not stop failed sync discovery.", error)
            }
            if (syncDiscoverySession === this) {
                syncDiscoverySession = null
            }
            releaseMulticastLockIfIdle()
            result.error(code, message, null)
        }

        private fun resolveNext() {
            if (finished || resolving || pending.isEmpty()) return
            resolving = true
            val serviceInfo = pending.removeFirst()
            try {
                manager.resolveService(serviceInfo, object : NsdManager.ResolveListener {
                    override fun onServiceResolved(resolvedService: NsdServiceInfo) {
                        if (finished) return
                        Log.i(
                            TAG,
                            "Sync service resolved: ${resolvedService.serviceName} " +
                                "${resolvedService.host?.hostAddress}:${resolvedService.port}.",
                        )
                        resolvedService.toDiscoveryMap()?.let { results.add(it) }
                        resolving = false
                        resolveNext()
                    }

                    override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                        if (finished) return
                        Log.w(TAG, "Sync service resolve failed: $errorCode")
                        resolving = false
                        resolveNext()
                    }
                })
            } catch (error: Exception) {
                Log.w(TAG, "Could not resolve sync service.", error)
                resolving = false
                resolveNext()
            }
        }
    }

    private data class PendingBackupSave(
        val sourcePath: String,
        val fileName: String,
        val result: MethodChannel.Result,
    )

    private data class PendingNearbyWifiPermission(
        val result: MethodChannel.Result,
        val onGranted: () -> Unit,
    )

    private data class SyncServiceRegistration(
        val deviceId: String,
        val port: Int,
        val protocolVersion: Int,
    )

    private fun initializeMlKitIfAvailable() {
        try {
            val mlKit = Class.forName("com.google.mlkit.common.MlKit")
            val initialize = mlKit.getMethod("initialize", android.content.Context::class.java)
            initialize.invoke(null, applicationContext)
        } catch (error: Exception) {
            Log.w(TAG, "ML Kit pre-initialization was unavailable.", error)
        }
    }

    private companion object {
        const val TAG = "DekonMainActivity"
        const val BACKUP_FILES_CHANNEL = "xyz.infinica.dekon/backup_files"
        const val APP_ACTIONS_CHANNEL = "xyz.infinica.dekon/app_actions"
        const val SYNC_DISCOVERY_CHANNEL = "xyz.infinica.dekon/sync_discovery"
        const val SAVE_BACKUP_REQUEST_CODE = 9101
        const val DEKON_SYNC_SERVICE_TYPE = "_dekon-sync._tcp"
        const val DEFAULT_DISCOVERY_TIMEOUT_MILLIS = 3000
        const val MAX_DISCOVERY_TIMEOUT_MILLIS = 10000
        const val NETWORK_REREGISTER_DELAY_MILLIS = 750L
        const val NEARBY_WIFI_PERMISSION_REQUEST_CODE = 9102
    }
}
