package com.secureapp.ghost_client

import android.content.Intent
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "ghost_chat/call"
    private val EVENT_CHANNEL = "ghost_chat/call_events"
    private var eventSink: EventChannel.EventSink? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )
        // Si viene de una llamada, ir directo sin PIN
        if (intent?.getBooleanExtra("accept_call", false) == true) {
            val prefs = getSharedPreferences("FlutterSharedPreferences", android.content.Context.MODE_PRIVATE)
            prefs.edit().putBoolean("flutter.incoming_call_active", true).apply()
        }
        handleCallIntent(intent)
        // Programar WorkManager para mantener servicio activo
        GhostWorker.schedule(this)

    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleCallIntent(intent)
    }

    private fun handleCallIntent(intent: Intent?) {
        if (intent?.getBooleanExtra("accept_call", false) == true) {
            val fromUser = intent.getStringExtra("from_user") ?: ""
            val isVideo = intent.getBooleanExtra("is_video", false)
            eventSink?.success(mapOf(
                "type" to "accept_call",
                "from_user" to fromUser,
                "is_video" to isVideo
            ))
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "registerPhoneAccount") {
                try {
                    GhostCallService.registerPhoneAccount(this)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("ERROR", e.message, null)
                }
            } else
            if (call.method == "showIncomingCall") {
                val fromUser = call.argument<String>("from_user") ?: ""
                val callerName = call.argument<String>("caller_name") ?: "Usuario"
                val isVideo = call.argument<Boolean>("is_video") ?: false
                val callId = call.argument<String>("call_id") ?: ""
                CallReceiver.showCallNotification(this, fromUser, callerName, isVideo, callId)
                result.success(true)
            } else {
                result.notImplemented()
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    // Verificar si hay intent pendiente
                    handleCallIntent(intent)
                }
                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            }
        )
    }

    override fun onPause() { super.onPause() }
    override fun onStop() { super.onStop() }
}
