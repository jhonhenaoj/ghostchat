package com.secureapp.ghost_client

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class MyFirebaseMessagingService : FirebaseMessagingService() {

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        super.onMessageReceived(remoteMessage)
        wakeScreen()
        val data = remoteMessage.data
        val type = data["type"] ?: remoteMessage.notification?.let { "message" } ?: return

        when (type) {
            "call" -> {
                val fromUser = data["from_user"] ?: ""
                val callerName = data["caller_name"] ?: data["title"] ?: "Usuario"
                val isVideo = data["is_video"] == "true"
                val callId = data["call_id"] ?: System.currentTimeMillis().toString()
                // Guardar datos de llamada para Flutter
                val prefs = getSharedPreferences("FlutterSharedPreferences", android.content.Context.MODE_PRIVATE)
                prefs.edit()
                    .putString("flutter.pending_call_from", fromUser)
                    .putString("flutter.pending_call_id", callId)
                    .putBoolean("flutter.pending_call_video", isVideo)
                    .apply()
                println("📞 Firebase: Datos de llamada - from: $fromUser, isVideo: $isVideo")
                // Usar ConnectionService (como WhatsApp) con fallback al sistema anterior
                GhostCallService.showIncomingCall(this, fromUser, callerName, isVideo, callId)
            }
            else -> {
                val title = data["title"] ?: remoteMessage.notification?.title ?: "Ghost Chat"
                val body = data["body"] ?: remoteMessage.notification?.body ?: "Nuevo mensaje"
                showMessageNotification(title, body)
            }
        }
    }

    override fun onNewToken(token: String) {
        super.onNewToken(token)
        // Guardar nuevo token localmente para enviarlo al servidor cuando abra la app
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        prefs.edit().putString("flutter.fcm_pending_token", token).apply()
    }

    private fun wakeScreen() {
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            val wl = pm.newWakeLock(
                PowerManager.FULL_WAKE_LOCK or
                PowerManager.ACQUIRE_CAUSES_WAKEUP or
                PowerManager.ON_AFTER_RELEASE,
                "GhostChat:WakeLock"
            )
            wl.acquire(5000L)
            wl.release()
        } catch (e: Exception) {}
    }

    private fun showMessageNotification(title: String, body: String) {
        val channelId = "ghost_chat_messages"
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val soundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            val audioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            val channel = NotificationChannel(
                channelId, "Mensajes", NotificationManager.IMPORTANCE_HIGH
            ).apply {
                enableLights(true)
                enableVibration(true)
                setShowBadge(true)
                setSound(soundUri, audioAttributes)
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            }
            notificationManager.createNotificationChannel(channel)
        }

        val intent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        val pendingIntent = PendingIntent.getActivity(
            this, System.currentTimeMillis().toInt(), intent,
            PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE
        )

        val soundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
        val notification = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setSound(soundUri)
            .setVibrate(longArrayOf(0, 500, 200, 500))
            .setContentIntent(pendingIntent)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .build()

        notificationManager.notify(System.currentTimeMillis().toInt(), notification)
    }
}
