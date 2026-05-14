package com.secureapp.ghost_client

import android.app.KeyguardManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

class CallReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        when (action) {
            "ACCEPT_CALL" -> {
                val fromUser = intent.getStringExtra("from_user") ?: ""
                val isVideo = intent.getBooleanExtra("is_video", false)
                NotificationManagerCompat.from(context).cancel(1001)
                // Guardar flag para saltar PIN
                val prefs = context.getSharedPreferences("FlutterSharedPreferences", android.content.Context.MODE_PRIVATE)
                prefs.edit().putBoolean("flutter.incoming_call_active", true).apply()
                val mainIntent = Intent(context, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                    putExtra("accept_call", true)
                    putExtra("from_user", fromUser)
                    putExtra("is_video", isVideo)
                }
                context.startActivity(mainIntent)
            }
            "DECLINE_CALL", "END_CALL" -> {
                // Cancelar todas las notificaciones de llamada
                NotificationManagerCompat.from(context).cancel(1001)
                NotificationManagerCompat.from(context).cancelAll()
            }
        }
    }

    companion object {
        fun showCallNotification(context: Context, fromUser: String, callerName: String, isVideo: Boolean, callId: String) {
            val channelId = "ghost_chat_calls"
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val ringtoneUri = android.media.RingtoneManager.getDefaultUri(android.media.RingtoneManager.TYPE_RINGTONE)
                val audioAttributes = android.media.AudioAttributes.Builder()
                    .setUsage(android.media.AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                    .setContentType(android.media.AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
                val channel = NotificationChannel(channelId, "Llamadas", NotificationManager.IMPORTANCE_HIGH).apply {
                    description = "Llamadas entrantes"
                    enableVibration(true)
                    vibrationPattern = longArrayOf(0, 1000, 500, 1000, 500, 1000)
                    setSound(ringtoneUri, audioAttributes)
                    lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
                }
                val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                manager.createNotificationChannel(channel)
            }

            val acceptIntent = Intent(context, CallReceiver::class.java).apply {
                action = "ACCEPT_CALL"
                putExtra("from_user", fromUser)
                putExtra("is_video", isVideo)
            }
            val declineIntent = Intent(context, CallReceiver::class.java).apply {
                action = "DECLINE_CALL"
            }
            val fullScreenIntent = Intent(context, CallActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra("from_user", fromUser)
                putExtra("caller_name", callerName)
                putExtra("is_video", isVideo)
                putExtra("call_id", callId)
            }

            val acceptPending = PendingIntent.getBroadcast(context, 0, acceptIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val declinePending = PendingIntent.getBroadcast(context, 1, declineIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val fullScreenPending = PendingIntent.getActivity(context, 2, fullScreenIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

            val title = if (isVideo) "📹 Videollamada entrante" else "📞 Llamada entrante"
            val notification = NotificationCompat.Builder(context, channelId)
                .setSmallIcon(android.R.drawable.ic_menu_call)
                .setContentTitle(title)
                .setContentText(callerName)
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setCategory(NotificationCompat.CATEGORY_CALL)
                .setFullScreenIntent(fullScreenPending, true)
                .setOngoing(true)
                .setAutoCancel(false)
                .addAction(android.R.drawable.ic_menu_call, "Contestar", acceptPending)
                .addAction(android.R.drawable.ic_delete, "Rechazar", declinePending)
                .build()

            NotificationManagerCompat.from(context).notify(1001, notification)

            // Siempre mostrar CallActivity para que funcione con app muerta
            try {
                context.startActivity(fullScreenIntent)
            } catch (e: Exception) {
                // Si falla, la notificacion fullscreen se encarga
            }
        }
    }
}
