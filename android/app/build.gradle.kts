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
