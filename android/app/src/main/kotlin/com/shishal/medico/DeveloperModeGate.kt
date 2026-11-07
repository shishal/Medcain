package com.shishal.medico

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.res.Configuration
import android.database.ContentObserver
import android.graphics.Color
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Locks MEDCAIN while Android Developer options or USB debugging is on.
 *
 * `adb screencap` / `adb screenrecord` can capture a FLAG_SECURE window.
 * Both need Developer options. Debug installs skip the check so
 * `flutter run` still works; profile and release do not.
 *
 * Dart asks [CHANNEL] for the current value and listens on [EVENT_CHANNEL]
 * for changes. A solid shield covers the Flutter view until Dart has
 * painted the lock screen, so a question frame cannot flash through.
 */
class DeveloperModeGate(private val activity: Activity) {
    private val handler = Handler(Looper.getMainLooper())
    private val channelName = CHANNEL

    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null
    private var observing = false
    private var lastPublished: Boolean? = null

    /** Dart painted the lock screen, so the native shield can come down. */
    private var flutterCovering = false

    private var shield: View? = null

    private val observer = object : ContentObserver(handler) {
        override fun onChange(selfChange: Boolean) {
            sync()
        }
    }

    private val poll = object : Runnable {
        override fun run() {
            sync()
            handler.postDelayed(this, POLL_MS)
        }
    }

    fun attach(messenger: BinaryMessenger) {
        methodChannel = MethodChannel(messenger, channelName).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "isEnabled" -> result.success(isBlocked())
                    "openSettings" -> {
                        openSettings()
                        result.success(null)
                    }
                    "releaseShield" -> {
                        releaseShield()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        eventChannel = EventChannel(messenger, EVENT_CHANNEL).also { channel ->
            channel.setStreamHandler(
                object : EventChannel.StreamHandler {
                    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                        eventSink = events
                        val blocked = isBlocked()
                        lastPublished = blocked
                        events.success(blocked)
                    }

                    override fun onCancel(arguments: Any?) {
                        eventSink = null
                    }
                },
            )
        }
    }

    fun start() {
        if (observing) return
        observing = true
        val resolver = activity.contentResolver
        for (name in WATCHED_SETTINGS) {
            resolver.registerContentObserver(
                Settings.Global.getUriFor(name),
                false,
                observer,
            )
            resolver.registerContentObserver(
                Settings.Secure.getUriFor(name),
                false,
                observer,
            )
        }
        sync()
    }

    fun onHostStart() {
        sync()
        handler.removeCallbacks(poll)
        handler.post(poll)
    }

    fun onHostStop() {
        handler.removeCallbacks(poll)
    }

    fun stop() {
        handler.removeCallbacks(poll)
        if (observing) {
            activity.contentResolver.unregisterContentObserver(observer)
            observing = false
        }
        eventSink = null
        methodChannel?.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
        methodChannel = null
        eventChannel = null
    }

    /**
     * True when this process should refuse to show content.
     * Debug builds return false so a dev phone can still open the app.
     */
    fun isBlocked(): Boolean = shouldEnforce() && isDeveloperModeOn()

    private fun shouldEnforce(): Boolean = BuildConfig.BUILD_TYPE != "debug"

    private fun isDeveloperModeOn(): Boolean = WATCHED_SETTINGS.any { flagOn(it) }

    private fun flagOn(name: String): Boolean {
        val resolver = activity.contentResolver
        return Settings.Global.getInt(resolver, name, 0) == 1 ||
            Settings.Secure.getInt(resolver, name, 0) == 1
    }

    fun sync() {
        val blocked = isBlocked()
        if (blocked && lastPublished != true) {
            // Rising edge: the pixels currently on screen may be a question.
            flutterCovering = false
        }
        if (!blocked) flutterCovering = false
        if (blocked && !flutterCovering) showShield() else removeShield()
        if (lastPublished != blocked) {
            lastPublished = blocked
            publish(blocked)
        }
    }

    private fun releaseShield() {
        if (!isBlocked()) return
        flutterCovering = true
        removeShield()
    }

    private fun publish(blocked: Boolean) {
        val sink = eventSink ?: return
        try {
            sink.success(blocked)
        } catch (_: Exception) {
            eventSink = null
        }
    }

    private fun openSettings() {
        try {
            activity.startActivity(Intent(Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS))
        } catch (_: ActivityNotFoundException) {
            try {
                activity.startActivity(Intent(Settings.ACTION_SETTINGS))
            } catch (_: ActivityNotFoundException) {
                // No settings activity on this device.
            }
        }
    }

    private fun showShield() {
        val root = activity.findViewById<ViewGroup>(android.R.id.content) ?: return
        val existing = shield
        if (existing != null) {
            if (existing.parent != root) {
                (existing.parent as? ViewGroup)?.removeView(existing)
                root.addView(existing, matchParent())
            }
            existing.bringToFront()
            return
        }
        val nightMode =
            activity.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK
        val night = nightMode == Configuration.UI_MODE_NIGHT_YES
        val view = View(activity).apply {
            setBackgroundColor(
                if (night) Color.parseColor("#0A0A0A") else Color.parseColor("#F4F4F5"),
            )
            isClickable = true
            isFocusable = true
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
        }
        root.addView(view, matchParent())
        shield = view
    }

    private fun removeShield() {
        val view = shield ?: return
        (view.parent as? ViewGroup)?.removeView(view)
        shield = null
    }

    private fun matchParent() = FrameLayout.LayoutParams(
        ViewGroup.LayoutParams.MATCH_PARENT,
        ViewGroup.LayoutParams.MATCH_PARENT,
    )

    companion object {
        const val CHANNEL = "com.shishal.medico/developer_mode"
        const val EVENT_CHANNEL = "com.shishal.medico/developer_mode/events"

        /** How often we re-read the setting while the app is in the foreground. */
        private const val POLL_MS = 300L

        private val WATCHED_SETTINGS = listOf(
            Settings.Global.DEVELOPMENT_SETTINGS_ENABLED,
            Settings.Global.ADB_ENABLED,
            // Wireless debugging. String so this compiles against older SDKs
            // that don't expose Settings.Global.ADB_WIFI_ENABLED.
            "adb_wifi_enabled",
        )
    }
}
