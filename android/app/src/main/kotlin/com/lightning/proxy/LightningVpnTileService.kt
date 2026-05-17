package com.lightning.proxy

import android.content.Context
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import androidx.annotation.RequiresApi
import com.lightning.proxy.service.LightningVpnService

@RequiresApi(Build.VERSION_CODES.N)
class LightningVpnTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        updateTile()
    }

    override fun onClick() {
        super.onClick()
        val isRunning = LightningVpnService.isServiceRunning
        
        if (isRunning) {
            val intent = Intent(this, LightningVpnService::class.java).apply {
                action = LightningVpnService.ACTION_STOP
            }
            startService(intent)
        } else {
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val lastConfig = prefs.getString("flutter.last_config", null)
            
            if (lastConfig != null) {
                val intent = Intent(this, LightningVpnService::class.java).apply {
                    action = LightningVpnService.ACTION_START
                    putExtra(LightningVpnService.EXTRA_CONFIG, lastConfig)
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(intent)
                } else {
                    startService(intent)
                }
            } else {
                val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
                if (launchIntent != null) {
                    launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivityAndCollapse(launchIntent)
                }
            }
        }
        updateTile()
    }

    private fun updateTile() {
        val tile = qsTile ?: return
        val isRunning = LightningVpnService.isServiceRunning
        
        if (isRunning) {
            tile.state = Tile.STATE_ACTIVE
            tile.label = "Lightning 已连接"
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                tile.subtitle = "正在保护您的网络"
            }
        } else {
            tile.state = Tile.STATE_INACTIVE
            tile.label = "Lightning 未连接"
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                tile.subtitle = "点击开始连接"
            }
        }
        tile.updateTile()
    }

    companion object {
        fun requestTileUpdate(context: Context) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                try {
                    requestListeningState(context, android.content.ComponentName(context, LightningVpnTileService::class.java))
                } catch (e: Exception) {
                    // ignore
                }
            }
        }
    }
}
