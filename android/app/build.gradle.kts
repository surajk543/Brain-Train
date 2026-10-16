import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

/** android/<name> as properties, empty when the file does not exist. */
fun localProperties(name: String): Properties = Properties().apply {
    val file = rootProject.file(name)
    if (file.exists()) file.inputStream().use { load(it) }
}

// Google Play Games Services app ID (docs/PLAY_GAMES.md): android/play_games.properties
// (playGamesAppId=<number>) or -PplayGamesAppId=<number>. Without it Play Games is off.
val playGamesAppId: String =
    ((findProperty("playGamesAppId") as String?)
        ?: localProperties("play_games.properties").getProperty("playGamesAppId")
        ?: "").trim()
require(playGamesAppId.all(Char::isDigit)) { "playGamesAppId must be the numeric Play Games app ID" }

// Release upload key (docs/PLAY_GAMES.md): android/key.properties.
val uploadKey = localProperties("key.properties")

// AdMob (docs/ADS.md): android/admob.properties (gitignored) with
//   admobAppId=ca-app-pub-<publisher>~<app>
//   rewardedAdUnitId=ca-app-pub-<publisher>/<unit>
// or -PadmobAppId=... -PrewardedAdUnitId=.... Without them the build uses
// Google's test IDs, which only ever show test ads.
val admobTestAppId = "ca-app-pub-3940256099942544~3347511713"
val admobTestRewardedAdUnitId = "ca-app-pub-3940256099942544/5224354917"
val admob = localProperties("admob.properties")
fun admobSetting(name: String, testValue: String): String =
    ((findProperty(name) as String?) ?: admob.getProperty(name) ?: testValue).trim()
val admobAppId = admobSetting("admobAppId", admobTestAppId)
val rewardedAdUnitId = admobSetting("rewardedAdUnitId", admobTestRewardedAdUnitId)
require(Regex("ca-app-pub-\\d+~\\d+").matches(admobAppId)) {
    "admobAppId must look like ca-app-pub-<publisher>~<app> (android/admob.properties)"
}
require(Regex("ca-app-pub-\\d+/\\d+").matches(rewardedAdUnitId)) {
    "rewardedAdUnitId must look like ca-app-pub-<publisher>/<unit> (android/admob.properties)"
}
val admobUsesTestIds = admobAppId == admobTestAppId || rewardedAdUnitId == admobTestRewardedAdUnitId
if (gradle.startParameter.taskNames.any { it.contains("Release", ignoreCase = true) }) {
    if (admobUsesTestIds) {
        // Error level: Flutter runs Gradle quietly, and this must be seen.
        logger.error(
            "WARNING: AdMob TEST IDs in a release build (rewarded ads will only ever be test ads). " +
                "Put the real IDs in android/admob.properties (docs/ADS.md) before publishing.",
        )
    } else if (admobAppId.substringBefore('~') != rewardedAdUnitId.substringBefore('/')) {
        logger.error("WARNING: admobAppId and rewardedAdUnitId belong to different AdMob accounts (android/admob.properties).")
    }
}

android {
    namespace = "com.sungamestudio.braintrain"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        resValues = true
    }

    defaultConfig {
        applicationId = "com.sungamestudio.braintrain"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Read by the manifest's APP_ID meta-data and by MainActivity.
        resValue("string", "game_services_project_id", playGamesAppId)
        // AdMob app ID (manifest meta-data) and the rewarded ad unit (read by
        // Dart through MainActivity's channel).
        resValue("string", "admob_app_id", admobAppId)
        resValue("string", "admob_rewarded_ad_unit_id", rewardedAdUnitId)
        manifestPlaceholders["playGamesEnabled"] = playGamesAppId.isNotEmpty().toString()
    }

    signingConfigs {
        if (!uploadKey.isEmpty()) {
            create("upload") {
                storeFile = rootProject.file(uploadKey.getProperty("storeFile"))
                storePassword = uploadKey.getProperty("storePassword")
                keyAlias = uploadKey.getProperty("keyAlias")
                keyPassword = uploadKey.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (uploadKey.isEmpty()) {
                logger.warn("android/key.properties not found: release builds are signed with the debug key (not for Play).")
                signingConfigs.getByName("debug")
            } else {
                signingConfigs.getByName("upload")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
