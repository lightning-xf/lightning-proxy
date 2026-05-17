package com.lightning.proxy.channel

import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import android.os.Handler
import android.os.Looper

object LogChannel {
    private const val CHANNEL_NAME = "com.lightning.proxy/log"
    private var channel: MethodChannel? = null
    private val handler = Handler(Looper.getMainLooper())

    fun register(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, CHANNEL_NAME)
    }

    fun log(level: String, message: String) {
        handler.post {
            channel?.invokeMethod("onLog", mapOf(
                "level" to level,
                "message" to message
            ))
        }
    }
}
