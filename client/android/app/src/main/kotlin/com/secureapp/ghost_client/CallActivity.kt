package com.secureapp.ghost_client

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.widget.ImageView
import java.net.URL
import kotlin.concurrent.thread
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.content.res.ColorStateList
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import android.widget.ImageButton
import android.widget.TextView
import androidx.core.app.NotificationManagerCompat

class CallActivity : Activity() {
    private var isSpeakerOn = false
    private lateinit var audioManager: AudioManager

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        }

        val keyguardManager = getSystemService(KEYGUARD_SERVICE) as KeyguardManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            keyguardManager.requestDismissKeyguard(this, null)
        }

        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        setContentView(R.layout.activity_call)

        val fromUser = intent.getStringExtra("from_user") ?: ""
        val callerName = intent.getStringExtra("caller_name") ?: "Usuario"
        val isVideo = intent.getBooleanExtra("is_video", false)

        findViewById<TextView>(R.id.callerName).text = callerName
        findViewById<TextView>(R.id.callType).text = if (isVideo) "📹 Videollamada entrante" else "📞 Llamada entrante"
        // Cargar foto de perfil
        thread {
            try {
                val url = java.net.URL("http://162.243.174.252:9090/avatars/$fromUser.jpg")
                val bitmap = BitmapFactory.decodeStream(url.openStream())
                runOnUiThread {
                    try { findViewById<ImageView>(R.id.callerAvatar).setImageBitmap(bitmap) } catch (_: Exception) {}
                }
            } catch (_: Exception) {}
        }

        val btnSpeaker = findViewById<ImageButton>(R.id.btnSpeaker)
        btnSpeaker.setOnClickListener {
            isSpeakerOn = !isSpeakerOn
            audioManager.isSpeakerphoneOn = isSpeakerOn
            btnSpeaker.backgroundTintList = ColorStateList.valueOf(
                if (isSpeakerOn) 0xFF00D4FF.toInt() else 0xFF3A3A4A.toInt()
            )
        }

        findViewById<ImageButton>(R.id.btnAccept).setOnClickListener {
            NotificationManagerCompat.from(this).cancel(1001)
            // Guardar flag para saltar PIN
            val prefs = getSharedPreferences("FlutterSharedPreferences", android.content.Context.MODE_PRIVATE)
            prefs.edit().putBoolean("flutter.incoming_call_active", true).apply()
            val mainIntent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra("accept_call", true)
                putExtra("from_user", fromUser)
                putExtra("is_video", isVideo)
            }
            startActivity(mainIntent)
            finish()
        }

        findViewById<ImageButton>(R.id.btnDecline).setOnClickListener {
            NotificationManagerCompat.from(this).cancel(1001)
            finish()
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        finish()
    }

    override fun onBackPressed() {
        super.onBackPressed()
        finish()
    }
}
