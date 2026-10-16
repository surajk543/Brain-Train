package com.sungamestudio.braintrain

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Tells Dart whether this build has a Play Games app ID, and its rewarded
        // ad unit (android/app/build.gradle.kts; docs/PLAY_GAMES.md, docs/ADS.md).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "brain_train/platform")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "playGamesConfigured" ->
                        result.success(getString(R.string.game_services_project_id).isNotBlank())
                    "rewardedAdUnitId" ->
                        result.success(getString(R.string.admob_rewarded_ad_unit_id))
                    else -> result.notImplemented()
                }
            }
    }
}
