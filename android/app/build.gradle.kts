plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.mikannqaq.river"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        val appId = "com.mikannqaq.river"
        applicationId = appId
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        val jpushAppKey =
            (project.findProperty("JPUSH_APPKEY") as? String)
                ?.trim()
                ?.ifEmpty { null } ?: "9d432f3526f8a81d6d4fbca7"
        val jpushChannel =
            (project.findProperty("JPUSH_CHANNEL") as? String)
                ?.trim()
                ?.ifEmpty { null } ?: "developer-default"
        manifestPlaceholders["JPUSH_PKGNAME"] = appId
        manifestPlaceholders["JPUSH_APPKEY"] = jpushAppKey
        manifestPlaceholders["JPUSH_CHANNEL"] = jpushChannel
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.webkit:webkit:1.12.1")
}

