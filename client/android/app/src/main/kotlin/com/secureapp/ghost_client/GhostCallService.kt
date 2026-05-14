package com.secureapp.ghost_client

import android.net.Uri
import android.telecom.CallAudioState
import android.telecom.Connection
import android.telecom.ConnectionRequest
import android.telecom.ConnectionService
import android.telecom.DisconnectCause
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.app.NotificationManager

class GhostConnection(
    private val context: Context,
    private val fromUser: String,
    private val callerName: String,
    private val isVideo: Boolean,
    private val callId: String
) : Connection() {

    init {
        setCallerDisplayName(callerName, android.telecom.TelecomManager.PRESENTATION_ALLOWED)
        setAddress(Uri.parse("tel:$fromUser"), android.telecom.TelecomManager.PRESENTATION_ALLOWED)
        connectionCapabilities = CAPABILITY_MUTE or CAPABILITY_SUPPORT_HOLD
        audioModeIsVoip = true
    }

    override fun onAnswer() {
        super.onAnswer()
        setActive()
        // Guardar flag y abrir app
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        prefs.edit()
            .putBoolean("flutter.incoming_call_active", true)
            .putString("flutter.pending_call_from", fromUser)
            .putBoolean("flutter.pending_call_video", isVideo)
            .apply()
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("accept_call", true)
            putExtra("from_user", fromUser)
            putExtra("is_video", isVideo)
        }
        context.startActivity(intent)
    }

    override fun onReject() {
        super.onReject()
        setDisconnected(DisconnectCause(DisconnectCause.REJECTED))
        destroy()
    }

    override fun onDisconnect() {
        super.onDisconnect()
        setDisconnected(DisconnectCause(DisconnectCause.LOCAL))
        destroy()
    }

    override fun onCallAudioStateChanged(state: CallAudioState) {}
}

class GhostCallService : ConnectionService() {

    override fun onCreateIncomingConnection(
        connectionManagerPhoneAccount: PhoneAccountHandle?,
        request: ConnectionRequest?
    ): Connection {
        val extras = request?.extras ?: Bundle()
        val fromUser = extras.getString("from_user", "")
        val callerName = extras.getString("caller_name", "Usuario")
        val isVideo = extras.getBoolean("is_video", false)
        val callId = extras.getString("call_id", "")

        return GhostConnection(applicationContext, fromUser, callerName, isVideo, callId)
    }

    override fun onCreateIncomingConnectionFailed(
        connectionManagerPhoneAccount: PhoneAccountHandle?,
        request: ConnectionRequest?
    ) {}

    companion object {
        fun registerPhoneAccount(context: Context): PhoneAccountHandle {
            val telecomManager = context.getSystemService(Context.TELECOM_SERVICE) as TelecomManager
            val handle = PhoneAccountHandle(
                ComponentName(context, GhostCallService::class.java),
                "GhostChat"
            )
            val account = android.telecom.PhoneAccount.builder(handle, "Ghost Chat")
                .setCapabilities(android.telecom.PhoneAccount.CAPABILITY_SELF_MANAGED)
                .build()
            telecomManager.registerPhoneAccount(account)
            return handle
        }

        fun showIncomingCall(
            context: Context,
            fromUser: String,
            callerName: String,
            isVideo: Boolean,
            callId: String
        ) {
            // Forzar siempre el sistema de notificaciones (más confiable)
            CallReceiver.showCallNotification(context, fromUser, callerName, isVideo, callId)
        }
    }
}
