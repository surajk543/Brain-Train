package com.sungamestudio.braintrain

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import com.google.android.gms.games.PlayGamesSdk
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Tells Dart whether this build has a Play Games app ID, and its rewarded
        // ad unit (android/app/build.gradle.kts; docs/PLAY_GAMES.md, docs/ADS.md);
        // opens the store page for the lobby's update card (docs/APP_UPDATES.md).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "brain_train/platform")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "playGamesConfigured" ->
                        result.success(getString(R.string.game_services_project_id).isNotBlank())
                    // Play Games starts only when Dart asks, for 13+ players (the
                    // library's init provider is off, so nothing signs in at launch).
                    "initPlayGames" -> {
                        val configured = getString(R.string.game_services_project_id).isNotBlank()
                        if (configured) PlayGamesSdk.initialize(applicationContext)
                        result.success(configured)
                    }
                    "rewardedAdUnitId" ->
                        result.success(getString(R.string.admob_rewarded_ad_unit_id))
                    "openUrl" -> result.success(openStoreUrl(call.argument<String>("url")))
                    else -> result.notImplemented()
                }
            }
    }

    // Opens a store link: `market://` in the Play Store app, `https` in
    // whatever handles it. False when nothing can (Dart then tries the next).
    private fun openStoreUrl(url: String?): Boolean {
        val uri = url?.let(Uri::parse) ?: return false
        val intent = Intent(Intent.ACTION_VIEW, uri)
        when (uri.scheme) {
            "market" -> intent.setPackage("com.android.vending")
            "https" -> {}
            else -> return false
        }
        return try {
            startActivity(intent)
            true
        } catch (e: ActivityNotFoundException) {
            false
        }
    }
}
