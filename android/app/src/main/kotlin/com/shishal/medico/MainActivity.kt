package com.shishal.medico

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    // Created with the activity, before onCreate, because super.onCreate
    // attaches the Flutter engine and calls configureFlutterEngine.
    private val developerModeGate = DeveloperModeGate(this)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ensureAnnouncementChannel()
        developerModeGate.start()
    }

    // FCM shows a lock-screen alert on this channel. The id matches the
    // send-announcement-push payload and the manifest default.
    private fun ensureAnnouncementChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        val channel = NotificationChannel(
            ANNOUNCEMENT_CHANNEL_ID,
            "Announcements",
            NotificationManager.IMPORTANCE_HIGH,
        )
        channel.description = "Messages published from MEDCAIN"
        manager.createNotificationChannel(channel)
    }

    companion object {
        const val ANNOUNCEMENT_CHANNEL_ID = "announcements"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        developerModeGate.attach(flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onStart() {
        super.onStart()
        developerModeGate.onHostStart()
    }

    override fun onResume() {
        super.onResume()
        developerModeGate.sync()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) developerModeGate.sync()
    }

    override fun onStop() {
        developerModeGate.onHostStop()
        super.onStop()
    }

    override fun onDestroy() {
        developerModeGate.stop()
        super.onDestroy()
    }
}
