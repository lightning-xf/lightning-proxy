package com.lightning.proxy.channel

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.net.VpnService
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.lightning.proxy.service.LightningVpnService
import com.lightning.proxy.kernel.KernelUtils
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class VpnChannel(private val activity: Activity) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL_NAME = "com.lightning.proxy/vpn"
        const val REQUEST_CODE_VPN = 100
        const val REQUEST_CODE_NOTIFICATION = 101
        private var channel: MethodChannel? = null

        fun updateStatus(isRunning: Boolean) {
            val messenger = channel ?: return
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                messenger.invokeMethod("onStatusChanged", isRunning)
            }
        }

        fun reportError(message: String) {
            val messenger = channel ?: return
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                messenger.invokeMethod("onError", message)
            }
        }
    }

    private var pendingConfig: String? = null

    fun register(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, CHANNEL_NAME)
        channel?.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        VpnLogChannel.sendLogToFlutter("[VpnChannel] 方法调用: ${call.method}", "debug")
        when (call.method) {
            "startProxy" -> {
                val config = call.argument<String>("config")
                val nodeName = call.argument<String>("nodeName")
                VpnLogChannel.sendLogToFlutter("[VpnChannel] startProxy: nodeName=$nodeName, config长度=${config?.length ?: 0}", "debug")
                if (config == null) {
                    VpnLogChannel.sendLogToFlutter("[VpnChannel] startProxy 错误: config 为空", "error")
                    result.error("INVALID_ARGUMENT", "Config is null", null)
                    return
                }

                // Save node name for notification
                if (nodeName != null) {
                    val prefs = activity.getSharedPreferences("lightning_prefs", Context.MODE_PRIVATE)
                    prefs.edit().putString("last_node_name", nodeName).apply()
                    VpnLogChannel.sendLogToFlutter("[VpnChannel] 已保存节点名称: $nodeName", "debug")
                }

                if (checkAndRequestNotificationPermission()) {
                    VpnLogChannel.sendLogToFlutter("[VpnChannel] 权限检查通过, 开始 VPN...", "debug")
                    startVpn(config)
                } else {
                    VpnLogChannel.sendLogToFlutter("[VpnChannel] 权限检查失败, 等待权限...", "warning")
                    pendingConfig = config
                }
                result.success(null)
            }
            "stopProxy" -> {
                VpnLogChannel.sendLogToFlutter("[VpnChannel] stopProxy 调用", "debug")
                stopVpn()
                result.success(null)
            }
            "getVpnStatus" -> {
                val status = LightningVpnService.isServiceRunning
                VpnLogChannel.sendLogToFlutter("[VpnChannel] getVpnStatus: $status", "debug")
                result.success(status)
            }
            "getCoreVersion" -> {
                val version = KernelUtils.getVersion()
                VpnLogChannel.sendLogToFlutter("[VpnChannel] getCoreVersion: $version", "debug")
                result.success(version)
            }
            "queryStats" -> {
                try {
                    val stats = KernelUtils.queryStats()
                    result.success(stats)
                } catch (e: Exception) {
                    VpnLogChannel.sendLogToFlutter("[VpnChannel] queryStats 异常: ${e.message}", "error")
                    result.success("0,0")
                }
            }
            "googlePing" -> {
                VpnLogChannel.sendLogToFlutter("[VpnChannel] googlePing 开始...", "debug")
                Thread {
                    val delay = KernelUtils.googlePing()
                    VpnLogChannel.sendLogToFlutter("[VpnChannel] googlePing 结果: $delay ms", "debug")
                    android.os.Handler(android.os.Looper.getMainLooper()).post {
                        result.success(delay)
                    }
                }.start()
            }
            "measureSingleDelay" -> {
                val config = call.argument<String>("config")
                VpnLogChannel.sendLogToFlutter("[VpnChannel] measureSingleDelay: config长度=${config?.length ?: 0}", "debug")
                Thread {
                    val delay = if (config != null) {
                        KernelUtils.measureSingleDelay(config)
                    } else {
                        VpnLogChannel.sendLogToFlutter("[VpnChannel] measureSingleDelay 错误: config 为空", "error")
                        -2L
                    }
                    activity.runOnUiThread { result.success(delay.toInt()) }
                }.start()
            }
            "measureBatchDelay" -> {
                val config = call.argument<String>("config")
                val count = call.argument<Int>("count")
                VpnLogChannel.sendLogToFlutter("[VpnChannel] measureBatchDelay: count=$count", "debug")
                Thread {
                    val results = if (config != null && count != null) {
                        KernelUtils.measureBatchDelay(config, count)
                    } else {
                        VpnLogChannel.sendLogToFlutter("[VpnChannel] measureBatchDelay 错误: 参数为空", "error")
                        ""
                    }
                    activity.runOnUiThread { result.success(results) }
                }.start()
            }
            "tcpPing" -> {
                val address = call.argument<String>("address")
                val port = call.argument<Int>("port")
                VpnLogChannel.sendLogToFlutter("[VpnChannel] tcpPing: $address:$port", "debug")
                Thread {
                    val delay = if (address != null && port != null) {
                        KernelUtils.tcpPing(address, port)
                    } else {
                        VpnLogChannel.sendLogToFlutter("[VpnChannel] tcpPing 错误: 参数为空", "error")
                        -2L
                    }
                    activity.runOnUiThread { result.success(delay.toInt()) }
                }.start()
            }
            "requestBatteryOptimization" -> {
                requestBatteryOptimization()
                result.success(null)
            }
            "isIgnoringBatteryOptimizations" -> {
                result.success(isIgnoringBatteryOptimizations())
            }
            "requestNotificationPermission" -> {
                val granted = checkAndRequestNotificationPermission()
                VpnLogChannel.sendLogToFlutter("[VpnChannel] requestNotificationPermission: $granted", "debug")
                result.success(granted)
            }
            "updateSettings" -> {
                val autoStart = call.argument<Boolean>("autoStart")
                val autoReconnect = call.argument<Boolean>("autoReconnect")
                val showTraffic = call.argument<Boolean>("showTraffic")
                VpnLogChannel.sendLogToFlutter("[VpnChannel] updateSettings: autoStart=$autoStart, autoReconnect=$autoReconnect", "debug")
                val prefs = activity.getSharedPreferences("lightning_prefs", Context.MODE_PRIVATE)
                val editor = prefs.edit()
                if (autoStart != null) editor.putBoolean("auto_start", autoStart)
                if (autoReconnect != null) editor.putBoolean("auto_reconnect", autoReconnect)
                if (showTraffic != null) editor.putBoolean("show_traffic", showTraffic)
                editor.apply()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun checkAndRequestNotificationPermission(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(activity, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                ActivityCompat.requestPermissions(activity, arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_CODE_NOTIFICATION)
                return false
            }
        }
        return true
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        val powerManager = activity.getSystemService(Context.POWER_SERVICE) as PowerManager
        return powerManager.isIgnoringBatteryOptimizations(activity.packageName)
    }

    private fun requestBatteryOptimization() {
        val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
        intent.data = Uri.parse("package:${activity.packageName}")
        activity.startActivity(intent)
    }

    private fun startVpn(config: String) {
        val intent = VpnService.prepare(activity)
        if (intent != null) {
            pendingConfig = config
            activity.startActivityForResult(intent, REQUEST_CODE_VPN)
        } else {
            executeStart(config)
        }
    }

    private fun stopVpn() {
        val intent = Intent(activity, LightningVpnService::class.java)
        intent.action = LightningVpnService.ACTION_STOP
        activity.startService(intent)
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQUEST_CODE_VPN && resultCode == Activity.RESULT_OK) {
            pendingConfig?.let {
                executeStart(it)
                pendingConfig = null
            }
        }
    }

    fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        if (requestCode == REQUEST_CODE_NOTIFICATION && grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            pendingConfig?.let {
                startVpn(it)
                pendingConfig = null
            }
        }
    }

    private fun executeStart(config: String) {
        val intent = Intent(activity, LightningVpnService::class.java)
        intent.action = LightningVpnService.ACTION_START
        intent.putExtra(LightningVpnService.EXTRA_CONFIG, config)
        activity.startService(intent)
    }
}
