plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

import java.io.File
import java.io.FileInputStream
import java.util.Properties

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

    // Release signing configuration - reads from android/key.properties (gitignored).
    // Only configured when key.properties exists AND complete; debug builds
    // always use the default debug keystore.
    val keyPropsFile = rootProject.file("key.properties")
    val keyPropsIsComplete = run {
        if (!keyPropsFile.exists()) return@run false
        val props = Properties()
        FileInputStream(keyPropsFile).use { props.load(it) }
        val required = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
        required.all { key -> (props.getProperty(key)?.trim()?.isNotEmpty() == true) }
    }
    if (keyPropsIsComplete) {
        val keyProps = Properties()
        FileInputStream(keyPropsFile).use { keyProps.load(it) }
        val storeFileValue = keyProps.getProperty("storeFile")!!.trim()
        val storePasswordValue = keyProps.getProperty("storePassword")!!.trim()
        val keyAliasValue = keyProps.getProperty("keyAlias")!!.trim()
        val keyPasswordValue = keyProps.getProperty("keyPassword")!!.trim()

        signingConfigs {
            create("release") {
                // Resolve relative storeFile paths against the android/ directory.
                val candidate = File(storeFileValue)
                storeFile = if (candidate.isAbsolute) candidate else rootProject.file(storeFileValue)
                storePassword = storePasswordValue
                keyAlias = keyAliasValue
                keyPassword = keyPasswordValue
            }
        }
    }

    buildTypes {
        release {
            // Use the release keystore only when fully configured; otherwise
            // fall back to debug signing at configuration time and fail with a
            // clear actionable error at execution time (see afterEvaluate below).
            // Never silently ship a production build signed with the debug key.
            if (keyPropsIsComplete) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                signingConfig = signingConfigs.getByName("debug")
            }
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    // Fail release packaging tasks with a clear message if signing is incomplete.
    afterEvaluate {
        val releaseGuard = Action<org.gradle.api.Task> {
            doFirst {
                if (!keyPropsIsComplete) {
                    throw IllegalStateException(
                        "Release signing configuration missing. Create android/key.properties from " +
                            "android/key.properties.example with storeFile, storePassword, keyAlias and keyPassword."
                    )
                }
            }
        }
        tasks.matching { it.name.startsWith("bundle") && it.name.contains("Release") }.configureEach {
            releaseGuard.execute(this)
        }
        tasks.matching { it.name.startsWith("assemble") && it.name.contains("Release") }.configureEach {
            releaseGuard.execute(this)
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