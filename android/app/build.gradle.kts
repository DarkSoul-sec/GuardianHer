plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.guardianher.app"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications (v10+) for java.time backporting.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // Pinned explicitly to match the installed toolchain
        // (Flutter 3.47.0, Android SDK platform 36 / build-tools 36.0.0).
        applicationId = "com.guardianher.app"
        minSdk = 24
        targetSdk = 36
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Release signing will be configured here in a later phase.
            // No keystore or signing secrets are committed to this repository.
            // For now the release build falls back to the debug key so
            // `flutter run --release` continues to work in development.
            signingConfig = signingConfigs.getByName("debug")
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

dependencies {
    // Java 8+ language/API desugaring for flutter_local_notifications.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    // LocalBroadcastManager for cross-component communication within the app.
    implementation("androidx.localbroadcastmanager:localbroadcastmanager:1.1.0")
}
