package com.lightning.proxy.channel

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel

object VpnLogChannel : EventChannel.StreamHandler {
    private const val CHANNEL_NAME = "com.lightning.proxy/vpn_logs"
    private var eventSink: EventChannel.EventSink? = null
    private val handler = Handler(Looper.getMainLooper())

    fun register(messenger: BinaryMessenger) {
        val channel = EventChannel(messenger, CHANNEL_NAME)
        channel.setStreamHandler(this)
    }

    fun sendLogToFlutter(msg: String, level: String = "info") {
        handler.post {
            // We can send a formatted string "level:message" or just message
            // To keep it compatible with the user's request for msg: String, 
            // but still pass the level to the UI.
            eventSink?.success("$level|$msg")
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }
}
