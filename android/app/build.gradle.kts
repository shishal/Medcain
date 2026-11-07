import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Local release signing (optional). Copy android/key.properties.example →
// android/key.properties and point storeFile at your upload keystore.
// Codemagic does not use this file — it injects CM_KEYSTORE_* when CI=true.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}

// Codemagic (and most CI) exports CI=true. Used to pick the injected keystore.
val isCi = System.getenv("CI") == "true"
val hasReleaseKeystore = isCi || keystorePropertiesFile.exists()

android {
    namespace = "com.shishal.medico"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        // DeveloperModeGate reads BuildConfig.BUILD_TYPE. AGP 8+ does not
        // generate BuildConfig unless this is on. The profile build type
        // copies debug, so it is also debuggable — FLAG_DEBUGGABLE cannot
        // tell a debug install from a profile one.
        buildConfig = true
    }

    defaultConfig {
        applicationId = "com.shishal.medico"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (isCi) {
                storeFile = file(
                    System.getenv("CM_KEYSTORE_PATH")
                        ?: error(
                            "CI release signing needs CM_KEYSTORE_PATH. " +
                                "Upload a keystore in Codemagic → Code signing identities " +
                                "and set android_signing in codemagic.yaml.",
                        ),
                )
                storePassword = System.getenv("CM_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("CM_KEY_ALIAS")
                keyPassword = System.getenv("CM_KEY_PASSWORD")
            } else if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storePassword = keystoreProperties.getProperty("storePassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
            }
        }
    }

    buildTypes {
        release {
            // Local `flutter run --release` still works without a keystore
            // (debug keys). Store / Codemagic builds must use the release keystore.
            signingConfig =
                if (hasReleaseKeystore) {
                    signingConfigs.getByName("release")
                } else {
                    signingConfigs.getByName("debug")
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
