package com.lightning.proxy.kernel

import com.lightning.proxy.channel.VpnLogChannel
import com.lightning.proxy.service.LightningVpnService
import libxray.Libxray
import android.system.Os
import android.util.Log
import java.net.HttpURLConnection
import java.net.InetSocketAddress
import java.net.Proxy
import java.net.Socket
import java.net.URL
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

object KernelUtils {
    private const val TAG = "KernelUtils"
    private val testLock = ReentrantLock()

    fun start(config: String): String {
        return Libxray.startXray(config)
    }

    fun stop(): String {
        return Libxray.stopXray()
    }

    /**
     * Extracts asset directory from config and sets environment variables.
     * Returns the actual JSON config.
     */
    private fun prepareConfig(config: String): String {
        if (!config.startsWith("__XRAY_ASSET_DIR__=")) {
            return config
        }
        
        val firstNewline = config.indexOf('\n')
        if (firstNewline == -1) return config
        
        val line = config.substring(0, firstNewline).trim()
        val assetDir = line.substring("__XRAY_ASSET_DIR__=".length)
        
        try {
            Os.setenv("XRAY_LOCATION_ASSET", assetDir, true)
            System.setProperty("xray.location.asset", assetDir)
            Log.d(TAG, "Set Xray asset dir for test: $assetDir")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to set asset dir: ${e.message}")
        }
        
        return config.substring(firstNewline + 1)
    }

    /**
     * Measures single node delay.
     * If VPN is running, it uses the existing instance to avoid connection interruption.
     */
    fun measureSingleDelay(config: String): Long {
        val isVpnRunning = LightningVpnService.isServiceRunning
        VpnLogChannel.sendLogToFlutter("[Kernel] measureSingleDelay 开始: isVpnRunning=$isVpnRunning", "debug")

        return testLock.withLock {
            var isStarted = false
            try {
                val actualConfig = prepareConfig(config)

                // We always try to start a temporary core on 10810 for testing
                if (!isVpnRunning) {
                    VpnLogChannel.sendLogToFlutter("[Kernel] VPN 未运行, 启动临时核心测速...", "debug")
                    Libxray.stopXray()
                    // Increased wait for port release
                    Thread.sleep(200)
                    val startResult = Libxray.startXray(actualConfig)
                if (startResult.isNotEmpty()) {
                    VpnLogChannel.sendLogToFlutter("[Kernel] ❌ 启动 Xray 测速失败: $startResult", "error")
                    return@withLock -2L
                }
                isStarted = true
                VpnLogChannel.sendLogToFlutter("[Kernel] Xray 已启动, 等待握手...", "debug")
                // Give it some time to handshake
                Thread.sleep(800)
                } else {
                    VpnLogChannel.sendLogToFlutter("[Kernel] VPN 正在运行, 跳过测速", "warning")
                    return@withLock -2L
                }

                VpnLogChannel.sendLogToFlutter("[Kernel] 发送 HTTPS 请求到 google.com...", "debug")
                val startTime = System.nanoTime()
                // Use unresolved address to ensure DNS is handled via proxy if possible
                val proxy = Proxy(Proxy.Type.SOCKS, InetSocketAddress.createUnresolved("127.0.0.1", 10810))
                val connection = URL("https://www.google.com/generate_204").openConnection(proxy) as HttpURLConnection

                connection.apply {
                    connectTimeout = 10000
                    readTimeout = 10000
                    useCaches = false
                    instanceFollowRedirects = false
                    requestMethod = "GET"
                    setRequestProperty("Connection", "close")
                    setRequestProperty("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36")
                }

                val responseCode = connection.responseCode
                val delay = if (responseCode == 204 || responseCode == 200) {
                    val ms = (System.nanoTime() - startTime) / 1_000_000
                    VpnLogChannel.sendLogToFlutter("[Kernel] ✅ 测速成功: ${ms}ms", "debug")
                    ms
                } else {
                    VpnLogChannel.sendLogToFlutter("[Kernel] ❌ 测速失败: HTTP $responseCode", "warning")
                    -2L
                }
                return@withLock delay
            } catch (e: Exception) {
                VpnLogChannel.sendLogToFlutter("[Kernel] ❌ 测速异常: ${e.message}", "error")
                return@withLock -2L
            } finally {
                if (isStarted) {
                    VpnLogChannel.sendLogToFlutter("[Kernel] 停止临时核心...", "debug")
                    try { Libxray.stopXray() } catch (e: Exception) {}
                }
            }
        }
    }

    /**
     * Measures the delay for multiple nodes in parallel.
     * config: The batch Xray config
     * count: Number of nodes to test
     * returns: Comma-separated delay values
     */
    fun measureBatchDelay(config: String, count: Int): String {
        val isVpnRunning = LightningVpnService.isServiceRunning
        
        return testLock.withLock {
            var isStarted = false
            try {
                if (isVpnRunning) {
                    return@withLock ""
                }

                val actualConfig = prepareConfig(config)
                Libxray.stopXray()
                Thread.sleep(150)
                
                Log.d(TAG, "Starting Xray for batch test, count: $count")
                val startResult = Libxray.startXray(actualConfig)
                if (startResult.isNotEmpty()) {
                    Log.e(TAG, "Failed to start Xray for batch test: $startResult")
                    return@withLock ""
                }
                isStarted = true
                Thread.sleep(1200)
                
                val results = LongArray(count) { -2L }
                val executors = Executors.newFixedThreadPool(minOf(count, 32))
                val latches = CountDownLatch(count)
                
                for (i in 0 until count) {
                    val port = 10811 + i
                    val index = i
                    executors.execute {
                        try {
                            Log.d(TAG, "Testing node $index on port $port")
                            val startTime = System.nanoTime()
                            // Use unresolved address for proxy
                            val proxy = Proxy(Proxy.Type.SOCKS, InetSocketAddress.createUnresolved("127.0.0.1", port))
                            val connection = URL("https://www.google.com/generate_204").openConnection(proxy) as HttpURLConnection
                            
                            connection.apply {
                                connectTimeout = 10000
                                readTimeout = 10000
                                useCaches = false
                                instanceFollowRedirects = false
                                requestMethod = "GET"
                                setRequestProperty("Connection", "close")
                                setRequestProperty("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36")
                            }
                            
                            val responseCode = connection.responseCode
                            Log.d(TAG, "Node $index response: $responseCode")
                            if (responseCode == 204 || responseCode == 200) {
                                results[index] = (System.nanoTime() - startTime) / 1_000_000
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "Node $index failed: ${e.message}")
                        } finally {
                            latches.countDown()
                        }
                    }
                }
                
                latches.await(20, TimeUnit.SECONDS)
                executors.shutdownNow()
                
                results.joinToString(",")
            } catch (e: Exception) {
                Log.e(TAG, "Batch test error: ${e.message}")
                ""
            } finally {
                if (isStarted) {
                    try { Libxray.stopXray() } catch (e: Exception) {}
                }
            }
        }
    }

    /**
     * Fast TCP ping to the node's address and port.
     * Does not require Xray to be started.
     * Enhanced with multiple retries and longer timeout.
     */
    fun tcpPing(address: String, port: Int): Long {
        var minDelay = Long.MAX_VALUE
        var successCount = 0
        
        // Test up to 5 times to handle network jitter/packet loss
        for (i in 0 until 5) {
            try {
                val startTime = System.nanoTime()
                val socket = java.net.Socket()
                // Increased timeout to 5000ms for slow/mobile networks
                socket.connect(java.net.InetSocketAddress(address, port), 5000)
                val delay = (System.nanoTime() - startTime) / 1_000_000
                socket.close()
                
                if (delay < minDelay) {
                    minDelay = delay
                }
                successCount++
                // Small gap between pings to avoid being flagged by firewalls
                Thread.sleep(100)
            } catch (e: Exception) {
                // Ignore failure of single ping and retry
            }
        }
        
        // If all 5 attempts failed, return -2 (Timeout)
        return if (successCount > 0) minDelay else -2L
    }

    fun getVersion(): String {
        return try {
            Libxray.getVersion()
        } catch (e: Exception) {
            "Unknown"
        }
    }

    /**
     * Measures delay by connecting to Google via the running Xray instance.
     * Uses HEAD request and disables keep-alive for the most lightweight probe.
     * Takes 3 measurements and returns the median value.
     */
    fun googlePing(): Long {
        val results = mutableListOf<Long>()
        
        for (i in 0 until 3) {
            try {
                val startTime = System.nanoTime()
                // Use the standard socks port 10808 defined in ConfigGenerator
                val proxy = Proxy(Proxy.Type.SOCKS, InetSocketAddress("127.0.0.1", 10808))
                // Use HTTP for better reliability in test
                val connection = URL("http://www.google.com/generate_204").openConnection(proxy) as HttpURLConnection
                
                connection.apply {
                    requestMethod = "GET"
                    connectTimeout = 5000
                    readTimeout = 5000
                    useCaches = false
                    instanceFollowRedirects = false
                    setRequestProperty("Connection", "close")
                    setRequestProperty("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36")
                }
                
                val responseCode = connection.responseCode
                if (responseCode == 204 || responseCode == 200) {
                    val delay = (System.nanoTime() - startTime) / 1_000_000
                    results.add(delay)
                }
                Thread.sleep(150)
            } catch (e: Exception) {
                // Ignore failure
            }
        }
        
        if (results.isEmpty()) return -2L
        
        results.sort()
        return results[results.size / 2]
    }

    fun queryStats(): String {
        return Libxray.queryStats()
    }
}