package com.lightning.proxy.kernel

import com.lightning.proxy.channel.VpnLogChannel
import com.lightning.proxy.service.LightningVpnService
import libxray.Libxray
import android.system.Os
import android.util.Log
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
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
    private val measureSemaphore = Semaphore(64) // 大幅放宽并发，对齐 v2rayNG
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    fun start(config: String): String {
        return Libxray.startXray(config)
    }

    fun stop(): String {
        return Libxray.stopXray()
    }

    /**
     * Measures the delay for multiple nodes in parallel using sandboxed Go engine.
     * configs: List of config payloads for each node
     * returns: Comma-separated delay values
     */
    fun measureBatchDelay(configs: List<String>): String {
        return runBlocking {
            val jobs = configs.map { config ->
                async {
                    measureSemaphore.withPermit {
                        try {
                            // 第 1 层超时：Kotlin 协程 6 秒硬超时 (同步放宽至 Go 层 5.5s 以上)
                            withTimeoutOrNull(6000L) {
                                // 调用 Go 层沙盒测速接口
                                val result = Libxray.measureRealDelay(config)
                                val parts = result.split("|")
                                val delay = parts[0].toLong()
                                if (parts.size > 1 && parts[1].isNotEmpty()) {
                                    VpnLogChannel.sendLogToFlutter("[Go-Debug] Batch: ${parts[1]}", "debug")
                                }
                                delay
                            } ?: -1L
                        } catch (e: Exception) {
                            Log.e(TAG, "Sandboxed measure failed: ${e.message}")
                            VpnLogChannel.sendLogToFlutter("[Go-Error] Sandboxed measure failed: ${e.message}", "error")
                            -1L
                        }
                    }
                }
            }
            jobs.awaitAll().joinToString(",")
        }
    }

    /**
     * Measures single node delay using sandboxed Go engine.
     */
    fun measureSingleDelay(config: String): Long {
        return try {
            // 第 1 层超时：Kotlin 协程 6 秒硬超时
            runBlocking {
                withTimeoutOrNull(6000L) {
                    val result = Libxray.measureRealDelay(config)
                    val parts = result.split("|")
                    val delay = parts[0].toLong()
                    if (parts.size > 1 && parts[1].isNotEmpty()) {
                        VpnLogChannel.sendLogToFlutter("[Go-Debug] Single: ${parts[1]}", "debug")
                    }
                    delay
                } ?: -1L
            }
        } catch (e: Exception) {
            Log.e(TAG, "Single sandboxed measure failed: ${e.message}")
            VpnLogChannel.sendLogToFlutter("[Go-Error] Single sandboxed measure failed: ${e.message}", "error")
            -1L
        }
    }

    /**
     * Fast TCP ping to the node's address and port.
     * Does not require Xray to be started.
     * Enhanced with multiple retries and longer timeout.
     */
    fun tcpPing(address: String, port: Int): Long {
        try {
            val startTime = System.nanoTime()
            val socket = java.net.Socket()
            // 铁证：TCP 握手超时放宽至 3000ms，捞回高延迟边缘节点
            socket.connect(java.net.InetSocketAddress(address, port), 3000)
            val delay = (System.nanoTime() - startTime) / 1_000_000
            socket.close()
            return delay
        } catch (e: Exception) {
            return -2L
        }
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