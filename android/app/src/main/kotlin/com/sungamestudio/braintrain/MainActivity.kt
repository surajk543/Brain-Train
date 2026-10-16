package com.sungamestudio.braintrain

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Tells Dart whether this build has a Play Games app ID (android/app/build.gradle.kts).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "brain_train/platform")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "playGamesConfigured" ->
                        result.success(getString(R.string.game_services_project_id).isNotBlank())
                    else -> result.notImplemented()
                }
            }
    }
}
