package com.lightning.proxy.service

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED || intent.action == Intent.ACTION_LOCKED_BOOT_COMPLETED) {
            Log.i("BootReceiver", "Device booted, checking for auto-start...")
            
            val prefs = context.getSharedPreferences("lightning_prefs", Context.MODE_PRIVATE)
            val autoStart = prefs.getBoolean("auto_start", true)
            val wasRunning = prefs.getBoolean("is_vpn_running", false)
            val lastConfig = prefs.getString("last_config", null)

            if (autoStart && wasRunning && lastConfig != null) {
                val serviceIntent = Intent(context, LightningVpnService::class.java).apply {
                    action = LightningVpnService.ACTION_START
                    putExtra(LightningVpnService.EXTRA_CONFIG, lastConfig)
                }
                
                try {
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                        context.startForegroundService(serviceIntent)
                    } else {
                        context.startService(serviceIntent)
                    }
                    Log.i("BootReceiver", "Started LightningVpnService automatically")
                } catch (e: Exception) {
                    Log.e("BootReceiver", "Failed to start service: ${e.message}")
                }
            }
        }
    }
}
