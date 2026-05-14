package com.secureapp.ghost_client

import android.content.Context
import android.content.Intent
import androidx.work.Worker
import androidx.work.WorkerParameters
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.ExistingPeriodicWorkPolicy
import java.util.concurrent.TimeUnit

class GhostWorker(context: Context, params: WorkerParameters) : Worker(context, params) {

    override fun doWork(): Result {
        try {
            // Renovar token FCM
            val prefs = applicationContext.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val userId = prefs.getString("flutter.user_id", "") ?: ""
            
            if (userId.isNotEmpty()) {
                // Iniciar MainActivity en background para renovar conexión
                val intent = Intent(applicationContext, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                    putExtra("from_worker", true)
                }
                // Solo renovar token FCM sin abrir UI
                com.google.firebase.messaging.FirebaseMessaging.getInstance().token
                    .addOnSuccessListener { token ->
                        prefs.edit().putString("flutter.fcm_pending_token", token).apply()
                    }
            }
        } catch (e: Exception) {
            // Silenciar errores
        }
        return Result.success()
    }

    companion object {
        fun schedule(context: Context) {
            val workRequest = PeriodicWorkRequestBuilder<GhostWorker>(
                12, TimeUnit.HOURS // Cada 12 horas
            ).build()

            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                "GhostChatWorker",
                ExistingPeriodicWorkPolicy.KEEP,
                workRequest
            )
        }
    }
}
