package com.shishal.medico

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    // Created with the activity, before onCreate, because super.onCreate
    // attaches the Flutter engine and calls configureFlutterEngine.
    private val developerModeGate = DeveloperModeGate(this)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        developerModeGate.start()
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
