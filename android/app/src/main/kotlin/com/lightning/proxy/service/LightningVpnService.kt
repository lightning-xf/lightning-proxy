package com.lightning.proxy.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import com.lightning.proxy.MainActivity
import android.system.Os
import android.net.LocalServerSocket
import android.net.LocalSocket
import com.lightning.proxy.channel.LogChannel
import com.lightning.proxy.channel.VpnChannel
import com.lightning.proxy.channel.VpnLogChannel
import com.lightning.proxy.LightningVpnTileService
import libxray.Libxray
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.isActive
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.io.InputStream
import java.nio.charset.Charset
import java.util.Locale
import java.util.concurrent.atomic.AtomicBoolean

class LightningVpnService : VpnService() {
    private val serviceScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var vpnInterface: ParcelFileDescriptor? = null
    @Volatile
    private var isRunning = false
    private val isStarting = AtomicBoolean(false)
    private val isStopping = AtomicBoolean(false)
    private var networkCallbackRegistered = false
    private var wakeLock: PowerManager.WakeLock? = null
    private var lastConfig: String? = null
    private var logcatProcess: Process? = null
    private var localServerSocket: LocalServerSocket? = null
    private val localSocketPath = "lightning_proxy_socket"

    // Traffic stats
    private val handler = Handler(Looper.getMainLooper())
    private var lastUp: Long = 0
    private var lastDown: Long = 0
    private var statsRunnable: Runnable? = null

    private val networkCallback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            super.onAvailable(network)
            Log.i(TAG, "Network available, checking for reconnect...")
            val prefs = getSharedPreferences("lightning_prefs", Context.MODE_PRIVATE)
            if (prefs.getBoolean("auto_reconnect", true) && !isRunning && !isStarting.get() && !isStopping.get() && lastConfig != null) {
                startVpn(lastConfig!!)
            }
        }

        override fun onLost(network: Network) {
            super.onLost(network)
            Log.i(TAG, "Network lost")
        }
    }

    companion object {
        private const val TAG = "LightningVpnService"
        private const val NOTIFICATION_ID = 1
        private const val CHANNEL_ID = "lightning_vpn_channel"

        const val ACTION_START = "com.lightning.proxy.START"
        const val ACTION_STOP = "com.lightning.proxy.STOP"
        const val EXTRA_CONFIG = "config"

        var isServiceRunning = false
            private set
    }

    override fun onCreate() {
        super.onCreate()
        val connectivityManager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val builder = NetworkRequest.Builder()
        connectivityManager.registerNetworkCallback(builder.build(), networkCallback)
        networkCallbackRegistered = true
    }

    private fun sendLogToUI(msg: String, level: String = "info") {
        VpnLogChannel.sendLogToFlutter(msg, level)
    }

    private fun startLocalSocketServer() {
        Thread {
            try {
                localServerSocket = LocalServerSocket(localSocketPath)
                Log.d(TAG, "Socket protection server started on $localSocketPath")
                sendLogToUI("▶ [系统] 正在启动 Socket 保护服务器...")
                sendLogToUI("✔ [系统] Socket 保护服务器已就绪 (防环路开启)")
                
                while (isRunning || isStarting.get()) {
                    val socket = localServerSocket?.accept() ?: break
                    handleLocalSocket(socket)
                }
            } catch (e: IOException) {
                if (isRunning) {
                    Log.e(TAG, "Socket server error: ${e.message}")
                }
            } finally {
                try {
                    localServerSocket?.close()
                } catch (e: Exception) {}
                localServerSocket = null
                Log.d(TAG, "Socket protection server thread exiting")
            }
        }.apply {
            name = "LocalSocketServerThread"
            start()
        }
    }

    private fun handleLocalSocket(socket: LocalSocket) {
        try {
            socket.use { s ->
                val fds = s.ancillaryFileDescriptors
                if (fds != null && fds.isNotEmpty()) {
                    for (fd in fds) {
                        try {
                            val field = java.io.FileDescriptor::class.java.getDeclaredField("descriptor")
                            field.isAccessible = true
                            val fdInt = field.getInt(fd)
                            if (fdInt != -1) {
                                protect(fdInt)
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "Failed to protect FD: ${e.message}")
                        }
                    }
                }
                s.outputStream.write(0)
            }
        } catch (e: Exception) {
            Log.w(TAG, "Error handling local socket: ${e.message}")
        }
    }

    private fun stopLocalSocketServer() {
        Log.i(TAG, "Stopping local socket server...")
        try {
            localServerSocket?.close()
            localServerSocket = null
        } catch (e: Exception) {
            Log.e(TAG, "Error closing local server socket: ${e.message}")
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        if (action == ACTION_START) {
            val config = intent.getStringExtra(EXTRA_CONFIG)
            if (config != null) {
                lastConfig = config
                startVpn(config)
            }
        } else if (action == ACTION_STOP) {
            stopVpn()
        }
        return START_STICKY
    }

    private fun startVpn(config: String) {
        VpnLogChannel.sendLogToFlutter("[Kotlin] ========== VPN 启动流程开始 ==========", "debug")
        VpnLogChannel.sendLogToFlutter("[Kotlin] 接收到的配置长度: ${config.length} 字符", "debug")

        if (isRunning || isStarting.get()) {
            VpnLogChannel.sendLogToFlutter("[Kotlin] VPN 已在运行或正在启动, 忽略重复请求", "warning")
            return
        }
        isStarting.set(true)
        isStopping.set(false)
        VpnLogChannel.sendLogToFlutter("正在启动 VPN 服务...", "info")
        startLogcatObserver()

        try {
            VpnLogChannel.sendLogToFlutter("[Kotlin] 步骤1: 获取 WakeLock", "debug")
            acquireWakeLock()
            VpnLogChannel.sendLogToFlutter("[Kotlin] WakeLock 已获取", "debug")

            // 1. Create Notification for Foreground Service
            VpnLogChannel.sendLogToFlutter("[Kotlin] 步骤2: 创建前台通知", "debug")
            createNotificationChannel()
            val notification = createNotification()
            VpnLogChannel.sendLogToFlutter("[Kotlin] 通知渠道已创建, SDK: ${Build.VERSION.SDK_INT}", "debug")

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_NONE)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            VpnLogChannel.sendLogToFlutter("[Kotlin] 前台服务已启动", "debug")

            // 2. Setup TUN Interface first so we can get the FD
            VpnLogChannel.sendLogToFlutter("[Kotlin] 步骤3: 配置 TUN 接口", "debug")

            // Extract proxy apps and bypass flag if present
            var actualConfig = config
            val proxyApps = mutableListOf<String>()
            var bypassSelected = false
            var allowLan = false
            var dnsServers = mutableListOf<String>()
            val lines = config.split("\n", limit = 15)
            VpnLogChannel.sendLogToFlutter("[Kotlin] 解析配置前缀, 共 ${lines.size} 行", "debug")

            for (line in lines) {
                if (line.startsWith("__XRAY_ASSET_DIR__=")) {
                    val assetDir = line.substring("__XRAY_ASSET_DIR__=".length)
                    VpnLogChannel.sendLogToFlutter("[Kotlin] 解析到资源目录: $assetDir", "debug")
                    if (assetDir.isNotEmpty()) {
                        try {
                            Os.setenv("XRAY_LOCATION_ASSET", assetDir, true)
                            System.setProperty("xray.location.asset", assetDir)
                            VpnLogChannel.sendLogToFlutter("[Kotlin] 环境变量已设置: XRAY_LOCATION_ASSET=$assetDir", "debug")
                        } catch (e: Exception) {
                            VpnLogChannel.sendLogToFlutter("[Kotlin] 设置环境变量失败: ${e.message}", "error")
                        }
                    }
                    actualConfig = actualConfig.replace(line + "\n", "")
                } else if (line.startsWith("__XRAY_PROXY_APPS__=")) {
                    val appsStr = line.substring("__XRAY_PROXY_APPS__=".length)
                    if (appsStr.isNotEmpty()) {
                        proxyApps.addAll(appsStr.split(","))
                        VpnLogChannel.sendLogToFlutter("[Kotlin] 解析到代理应用: $appsStr", "debug")
                    }
                    actualConfig = actualConfig.replace(line + "\n", "")
                } else if (line.startsWith("__XRAY_BYPASS_APPS__=")) {
                    bypassSelected = line.substring("__XRAY_BYPASS_APPS__=".length).toBoolean()
                    VpnLogChannel.sendLogToFlutter("[Kotlin] 解析到绕过模式: bypassSelected=$bypassSelected", "debug")
                    actualConfig = actualConfig.replace(line + "\n", "")
                } else if (line.startsWith("__XRAY_ALLOW_LAN__=")) {
                    allowLan = line.substring("__XRAY_ALLOW_LAN__=".length).toBoolean()
                    VpnLogChannel.sendLogToFlutter("[Kotlin] 解析到 LAN 允许: allowLan=$allowLan", "debug")
                    actualConfig = actualConfig.replace(line + "\n", "")
                } else if (line.startsWith("__XRAY_DNS_SERVERS__=")) {
                    val dnsStr = line.substring("__XRAY_DNS_SERVERS__=".length)
                    if (dnsStr.isNotEmpty()) {
                        dnsServers.addAll(dnsStr.split(",").map { it.trim() })
                        VpnLogChannel.sendLogToFlutter("[Kotlin] 解析到 DNS 服务器: $dnsServers", "debug")
                    }
                    actualConfig = actualConfig.replace(line + "\n", "")
                }
            }
            VpnLogChannel.sendLogToFlutter("[Kotlin] ========== TUN 接口配置 ==========", "debug")
            VpnLogChannel.sendLogToFlutter("[Kotlin] MTU: 1350, 地址: 172.19.0.1/24", "debug")
            VpnLogChannel.sendLogToFlutter("[Kotlin] 路由: 0.0.0.0/0", "debug")

            val builder = Builder()
                .setSession("Lightning VPN")
                .setMtu(1350) // Reduced MTU for UDP/KCP overhead
                .addAddress("172.19.0.1", 24)
                .addRoute("0.0.0.0", 0)

            if (dnsServers.isEmpty()) {
                VpnLogChannel.sendLogToFlutter("[Kotlin] DNS: 使用默认服务器 (8.8.8.8, 1.1.1.1)", "debug")
                builder.addDnsServer("8.8.8.8")
                builder.addDnsServer("1.1.1.1")
            } else {
                VpnLogChannel.sendLogToFlutter("[Kotlin] DNS: 使用自定义服务器 $dnsServers", "debug")
                for (dns in dnsServers) {
                    try {
                        builder.addDnsServer(dns)
                    } catch (e: Exception) {
                        VpnLogChannel.sendLogToFlutter("[Kotlin] 添加 DNS 服务器失败: $dns, ${e.message}", "warning")
                    }
                }
            }
            builder.setBlocking(true)
            
            // [Fix] 彻底封杀应用自身的 UDP 回环
            // 物理截断 Hysteria2 等协议的底层 UDP 死锁
            try {
                builder.addDisallowedApplication(packageName)
                VpnLogChannel.sendLogToFlutter("[Kotlin] 应用自身已排除出 VPN: $packageName", "debug")
            } catch (e: Exception) {
                VpnLogChannel.sendLogToFlutter("[Kotlin] 排除自身应用失败: ${e.message}", "warning")
            }

            VpnLogChannel.sendLogToFlutter("[Kotlin] 阻塞模式: 已启用", "debug")

            // CRITICAL: Allow LAN Gateway functionality
            if (allowLan) {
                VpnLogChannel.sendLogToFlutter("[Kotlin] LAN 网关模式: 已启用", "debug")
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    Log.i(TAG, "LAN Gateway enabled: allowBypass set to true")
                    builder.allowBypass()
                }

                // Exclude common LAN subnets to allow direct local communication
                try {
                    builder.addRoute("192.168.0.0", 16)
                    builder.addRoute("10.0.0.0", 8)
                    builder.addRoute("172.16.0.0", 12)
                    VpnLogChannel.sendLogToFlutter("[Kotlin] LAN 排除路由: 192.168.0.0/16, 10.0.0.0/8, 172.16.0.0/12", "debug")
                } catch (e: Exception) {
                    VpnLogChannel.sendLogToFlutter("[Kotlin] 添加 LAN 路由失败: ${e.message}", "warning")
                }
            }

            // Bypass itself
            builder.addDisallowedApplication(packageName)
            VpnLogChannel.sendLogToFlutter("[Kotlin] 应用自身已排除出 VPN: $packageName", "debug")

            // Add allowed/disallowed applications for split tunneling
            if (proxyApps.isNotEmpty()) {
                VpnLogChannel.sendLogToFlutter("[Kotlin] 分流隧道: bypassSelected=$bypassSelected, 应用数: ${proxyApps.size}", "debug")
                for (app in proxyApps) {
                    try {
                        if (bypassSelected) {
                            builder.addDisallowedApplication(app)
                        } else {
                            builder.addAllowedApplication(app)
                        }
                    } catch (e: Exception) {
                        VpnLogChannel.sendLogToFlutter("[Kotlin] 添加应用失败: $app, ${e.message}", "warning")
                    }
                }
            }

            VpnLogChannel.sendLogToFlutter("[Kotlin] 正在建立 TUN 接口...", "debug")
            vpnInterface = builder.establish()
            if (vpnInterface == null) {
                val error = "无法建立 TUN 接口，可能被其他 VPN 占用"
                VpnLogChannel.sendLogToFlutter("[Kotlin] TUN 接口建立失败: $error", "error")
                stopSelf()
                return
            }

            val fd = vpnInterface!!.fd
            VpnLogChannel.sendLogToFlutter("[Kotlin] TUN 接口建立成功! FD: $fd", "info")

            // 3. Set Environment Variables for Xray Core & Go Runtime
            VpnLogChannel.sendLogToFlutter("[Kotlin] ========== 设置环境变量 ==========", "debug")
            try {
                // Use the assetDir parsed from config if available, otherwise fallback
                val finalAssetDir = if (System.getProperty("xray.location.asset")?.isNotEmpty() == true) {
                    System.getProperty("xray.location.asset")
                } else {
                    File(filesDir, "data").absolutePath
                }
                
                VpnLogChannel.sendLogToFlutter("[Kotlin] 最终资源目录: $finalAssetDir", "debug")
                Os.setenv("XRAY_LOCATION_ASSET", finalAssetDir, true)
                Os.setenv("xray.location.asset", finalAssetDir, true) // Add lowercase as well
                Os.setenv("XRAY_SOCK_PROTECT_PATH", localSocketPath, true)
                
                // Go Runtime Memory Optimization
                Os.setenv("GOGC", "50", true)
                Os.setenv("GOMEMLIMIT", "100MiB", true)

                System.setProperty("xray.location.asset", finalAssetDir)
            } catch (e: Exception) {
                VpnLogChannel.sendLogToFlutter("[Kotlin] 设置环境变量失败: ${e.message}", "error")
            }

            VpnLogChannel.sendLogToFlutter("[Kotlin] ========== 准备启动 Xray 核心 ==========", "debug")
            VpnLogChannel.sendLogToFlutter("[Kotlin] TUN FD: $fd", "debug")
            VpnLogChannel.sendLogToFlutter("[Kotlin] 配置长度: ${actualConfig.length} 字符", "debug")

            val configPayload = "__XRAY_TUN_FD__=$fd\n$actualConfig"
            VpnLogChannel.sendLogToFlutter("[Kotlin] Payload 总长度: ${configPayload.length} 字符", "debug")
            dumpConfigSnapshot(actualConfig)

            // 5. Start Socket Protection Server before Xray
            VpnLogChannel.sendLogToFlutter("[Kotlin] 步骤4: 启动 Socket 保护服务器...", "debug")
            startLocalSocketServer()

            VpnLogChannel.sendLogToFlutter("[Kotlin] 步骤5: 在协程中启动 Xray 核心...", "info")
            serviceScope.launch {
                val result = try {
                    Libxray.startXray(configPayload)
                } catch (e: Exception) {
                    VpnLogChannel.sendLogToFlutter("[Kotlin] Libxray.startXray 抛出异常: ${e.message}", "error")
                    e.message ?: "Unknown error during Xray start"
                }

                withContext(Dispatchers.Main) {
                    if (result.isNotEmpty()) {
                        val error = "Xray 启动失败: $result"
                        VpnLogChannel.sendLogToFlutter("[Kotlin] ❌ Xray 启动失败: $error", "error")

                        // Report error to Flutter
                        VpnChannel.reportError(result)

                        stopVpn()
                    } else {
                        VpnLogChannel.sendLogToFlutter("[Kotlin] ✅ Xray 核心启动成功!", "info")
                        isRunning = true
                        isServiceRunning = true
                        isStarting.set(false)
                        VpnChannel.updateStatus(true)
                        com.lightning.proxy.LightningVpnTileService.requestTileUpdate(this@LightningVpnService)
                        VpnLogChannel.sendLogToFlutter("[Kotlin] VPN 完全启动! isRunning=true", "info")

                        // Start traffic stats update
                        startStatsUpdate()

                        // Save state for auto-restart
                        val prefs = getSharedPreferences("lightning_prefs", Context.MODE_PRIVATE)
                        prefs.edit().putBoolean("is_vpn_running", true).putString("last_config", actualConfig).apply()
                    }
                }
            }

        } catch (e: Exception) {
            isStarting.set(false)
            val error = "启动 VPN 时发生错误: ${e.message}"
            VpnLogChannel.sendLogToFlutter("[Kotlin] ❌ 启动异常: $error", "error")
            VpnLogChannel.sendLogToFlutter("[Kotlin] 异常堆栈: ${e.stackTrace}", "debug")
            stopVpn()
        }
    }

    private fun stopVpn() {
        VpnLogChannel.sendLogToFlutter("[Kotlin] ========== VPN 停止流程开始 ==========", "debug")
        if (!isRunning && !isStarting.get() && !isStopping.get()) {
            VpnLogChannel.sendLogToFlutter("[Kotlin] VPN 未运行, 无需停止", "debug")
            return
        }
        isStopping.set(true)
        isStarting.set(false)
        VpnLogChannel.sendLogToFlutter("[Kotlin] 步骤1: 停止 Libxray...", "debug")
        try {
            Libxray.stopXray()
            VpnLogChannel.sendLogToFlutter("[Kotlin] Libxray.stopXray() 完成", "debug")

            VpnLogChannel.sendLogToFlutter("[Kotlin] 步骤2: 停止 Socket 服务器...", "debug")
            stopLocalSocketServer()
            VpnLogChannel.sendLogToFlutter("[Kotlin] Socket 服务器已停止", "debug")

            VpnLogChannel.sendLogToFlutter("[Kotlin] 步骤3: 关闭 TUN 接口...", "debug")
            vpnInterface?.close()
            vpnInterface = null
            VpnLogChannel.sendLogToFlutter("[Kotlin] TUN 接口已关闭", "debug")

            VpnLogChannel.sendLogToFlutter("[Kotlin] 步骤4: 停止前台服务...", "debug")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
            VpnLogChannel.sendLogToFlutter("[Kotlin] 前台服务已停止", "debug")

            isRunning = false
            isServiceRunning = false
            VpnChannel.updateStatus(false)
            com.lightning.proxy.LightningVpnTileService.requestTileUpdate(this)

            VpnLogChannel.sendLogToFlutter("[Kotlin] 步骤5: 释放 WakeLock...", "debug")
            releaseWakeLock()
            VpnLogChannel.sendLogToFlutter("[Kotlin] WakeLock 已释放", "debug")

            val prefs = getSharedPreferences("lightning_prefs", Context.MODE_PRIVATE)
            prefs.edit().putBoolean("is_vpn_running", false).apply()

            VpnLogChannel.sendLogToFlutter("[Kotlin] ✅ VPN 停止完成", "info")
        } catch (e: Exception) {
            VpnLogChannel.sendLogToFlutter("[Kotlin] ❌ 停止 VPN 时发生错误: ${e.message}", "error")
        } finally {
            isStopping.set(false)
        }
        stopSelf()
    }

    private fun acquireWakeLock() {
        if (wakeLock == null) {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Lightning:VpnWakeLock")
            wakeLock?.acquire()
        }
    }

    private fun releaseWakeLock() {
        wakeLock?.let {
            if (it.isHeld) {
                it.release()
            }
        }
        wakeLock = null
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val serviceChannel = NotificationChannel(
                CHANNEL_ID,
                "Lightning VPN Service Channel",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "VPN 运行状态通知"
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(serviceChannel)
        }
    }

    private fun startLogcatObserver() {
        if (logcatProcess != null) return
        
        serviceScope.launch(Dispatchers.IO) {
            try {
                // 清除旧日志
                Runtime.getRuntime().exec("logcat -c")
                
                // [Fix] 同时监听 Logcat 和 Xray 专用日志文件
                val assetDir = File(applicationContext.filesDir, "last_xray_config.json").parentFile
                val accessLog = File(assetDir, "xray_access.log")
                val errorLog = File(assetDir, "xray_error.log")

                // 启动子协程轮询 Xray 本地日志文件
                launch {
                    val files = listOf(accessLog, errorLog)
                    val readers = files.map { if (it.exists()) it.bufferedReader() else null }.toMutableList()
                    
                    while (isActive) {
                        files.forEachIndexed { index, file ->
                            if (readers[index] == null && file.exists()) {
                                readers[index] = file.bufferedReader()
                            }
                            readers[index]?.let { reader ->
                                var line = reader.readLine()
                                while (line != null) {
                                    // 核心开发者明确要求：所有内核级别的原生日志，必须以 debug 级别推给 UI 进行渲染
                                    VpnLogChannel.sendLogToFlutter("[Xray-Core] $line", "debug")
                                    line = reader.readLine()
                                }
                            }
                        }
                        kotlinx.coroutines.delay(500) // 每 500ms 检查一次新日志
                    }
                }

                logcatProcess = Runtime.getRuntime().exec("logcat -s libxray:V Xray:V LightningVpnService:V *:E")
                
                val reader = logcatProcess?.inputStream?.bufferedReader()
                reader?.forEachLine { line ->
                    if (line.contains("libxray") || line.contains("Xray") || line.contains("FATAL") || line.contains("Exception")) {
                        val level = when {
                            line.contains(" E ") || line.contains("FATAL") || line.contains("[Error]") -> "error"
                            line.contains(" W ") || line.contains("[Warning]") -> "warning"
                            line.contains(" D ") || line.contains("[Debug]") -> "debug"
                            else -> "info"
                        }
                        VpnLogChannel.sendLogToFlutter(line, level)
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Logcat observer error: ${e.message}")
            }
        }
    }

    private fun stopLogcatObserver() {
        logcatProcess?.destroy()
        logcatProcess = null
    }

    private fun dumpConfigSnapshot(config: String) {
        try {
            val file = File(filesDir, "last_xray_config.json")
            FileOutputStream(file).use { output ->
                output.write(config.toByteArray(Charset.forName("UTF-8")))
            }
            VpnLogChannel.sendLogToFlutter("Xray 配置快照已写入: ${file.absolutePath}", "debug")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to dump config snapshot: ${e.message}")
        }
    }

    private fun startStatsUpdate() {
        statsRunnable = object : Runnable {
            override fun run() {
                if (!isRunning) return
                
                val stats = try {
                    val raw = Libxray.queryStats()
                    if (raw.isNotEmpty() && raw.contains(",")) {
                        raw
                    } else {
                        ""
                    }
                } catch (e: Exception) {
                    ""
                }
                
                val parts = stats.split(",").map { it.trim() }
                if (parts.size >= 2) {
                    val currentUp = parts[0].toLongOrNull() ?: 0L
                    val currentDown = parts[1].toLongOrNull() ?: 0L
                    
                    // Xray Stats 计数器是累计值。如果当前值小于上次记录值，说明核心重启了。
                    // 计算瞬时网速：当前累计值 - 上次累计值
                    val upSpeed = if (lastUp > 0 && currentUp >= lastUp) currentUp - lastUp else 0L
                    val downSpeed = if (lastDown > 0 && currentDown >= lastDown) currentDown - lastDown else 0L
                    
                    lastUp = currentUp
                    lastDown = currentDown
                    
                    updateNotification(upSpeed, downSpeed, currentUp, currentDown)
                } else {
                    updateNotification(0, 0, lastUp, lastDown)
                }
                
                if (isRunning) {
                    handler.postDelayed(this, 1000)
                }
            }
        }
        handler.post(statsRunnable!!)
    }

    private fun stopStatsUpdate() {
        statsRunnable?.let { handler.removeCallbacks(it) }
        statsRunnable = null
        lastUp = 0
        lastDown = 0
    }

    private fun updateNotification(upSpeed: Long, downSpeed: Long, totalUp: Long, totalDown: Long) {
        val prefs = getSharedPreferences("lightning_prefs", Context.MODE_PRIVATE)
        val showTraffic = prefs.getBoolean("show_traffic", true)
        val nodeName = prefs.getString("last_node_name", "已连接")
        
        if (!showTraffic) {
            val notification = createNotification()
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.notify(NOTIFICATION_ID, notification)
            return
        }

        val upSpeedStr = formatSpeed(upSpeed)
        val downSpeedStr = formatSpeed(downSpeed)
        val totalUpStr = formatTraffic(totalUp)
        val totalDownStr = formatTraffic(totalDown)

        val contentText = "↑ $upSpeedStr   ↓ $downSpeedStr"
        val bigText = "实时网速：↑ $upSpeedStr   ↓ $downSpeedStr\n累计流量：上传 $totalUpStr   下载 $totalDownStr"
        
        val notificationIntent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0, notificationIntent,
            PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Lightning: $nodeName")
            .setContentText(contentText)
            .setStyle(NotificationCompat.BigTextStyle().bigText(bigText))
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(pendingIntent)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .build()

        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(NOTIFICATION_ID, notification)
    }

    private fun formatSpeed(bytes: Long): String {
        val speed = bytes.toDouble()
        return when {
            speed >= 1024 * 1024 -> String.format(Locale.US, "%.1f MB/s", speed / (1024 * 1024))
            speed >= 1024 -> String.format(Locale.US, "%.1f KB/s", speed / 1024)
            else -> String.format(Locale.US, "%d B/s", bytes)
        }
    }

    private fun formatTraffic(bytes: Long): String {
        val traffic = bytes.toDouble()
        return when {
            traffic >= 1024 * 1024 * 1024 -> String.format(Locale.US, "%.2f GB", traffic / (1024 * 1024 * 1024))
            traffic >= 1024 * 1024 -> String.format(Locale.US, "%.2f MB", traffic / (1024 * 1024))
            traffic >= 1024 -> String.format(Locale.US, "%.2f KB", traffic / 1024)
            else -> String.format(Locale.US, "%d B", bytes)
        }
    }

    private fun createNotification(): Notification {
        val notificationIntent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0, notificationIntent,
            PendingIntent.FLAG_IMMUTABLE
        )

        val prefs = getSharedPreferences("lightning_prefs", Context.MODE_PRIVATE)
        val showTraffic = prefs.getBoolean("show_traffic", true)
        val nodeName = prefs.getString("last_node_name", "已连接")

        val contentText = if (showTraffic && isRunning) {
            "正在计算网速..."
        } else {
            "您的网络流量正受加密隧道保护"
        }

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Lightning: $nodeName")
            .setContentText(contentText)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(pendingIntent)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setOngoing(true)
            .build()
    }

    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        if (level >= TRIM_MEMORY_RUNNING_CRITICAL || level == TRIM_MEMORY_BACKGROUND) {
            Log.i(TAG, "System memory low (level: $level), triggering Go memory free")
            try {
                // Libxray.freeMemory() // Disabled until libxray.aar is updated with this function
            } catch (e: Exception) {
                // ignore
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        serviceScope.cancel()
        isServiceRunning = false
        if (networkCallbackRegistered) {
            val connectivityManager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            connectivityManager.unregisterNetworkCallback(networkCallback)
            networkCallbackRegistered = false
        }
        stopVpn()
    }

    override fun onRevoke() {
        super.onRevoke()
        stopVpn()
    }
}
