package com.lightning.proxy

import android.content.Intent
import com.lightning.proxy.channel.LogChannel
import com.lightning.proxy.channel.VpnChannel
import com.lightning.proxy.channel.VpnLogChannel
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var vpnChannel: VpnChannel? = null
    private val APP_CHANNEL = "com.lightning.proxy/apps"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        vpnChannel = VpnChannel(this)
        vpnChannel?.register(flutterEngine.dartExecutor.binaryMessenger)
        LogChannel.register(flutterEngine.dartExecutor.binaryMessenger)
        VpnLogChannel.register(flutterEngine.dartExecutor.binaryMessenger)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, APP_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getInstalledApps") {
                val apps = getInstalledApps()
                result.success(apps)
            } else {
                result.notImplemented()
            }
        }
    }

    private fun getInstalledApps(): List<Map<String, Any>> {
        val pm = packageManager
        // 尝试获取所有已安装应用，包含禁用的
        val apps = pm.getInstalledApplications(PackageManager.MATCH_DISABLED_COMPONENTS or PackageManager.GET_META_DATA)
        val appList = mutableListOf<Map<String, Any>>()
        for (app in apps) {
            // 过滤掉不可启动的应用（可选，但通常代理需要过滤这些）
            // 如果用户希望看到所有应用，则不进行 launchIntent 过滤
            val isSystemApp = (app.flags and ApplicationInfo.FLAG_SYSTEM) != 0
            val map = mapOf(
                "name" to pm.getApplicationLabel(app).toString(),
                "packageName" to app.packageName,
                "isSystem" to isSystemApp
            )
            appList.add(map)
        }
        return appList
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        vpnChannel?.onActivityResult(requestCode, resultCode, data)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        vpnChannel?.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }
}
