plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing credentials are injected by the local release environment or
// CI secret store. Never commit a keystore or passwords to this repository.
val releaseStoreFile = providers.environmentVariable("KAM_RELEASE_STORE_FILE").orNull
val releaseStorePassword = providers.environmentVariable("KAM_RELEASE_STORE_PASSWORD").orNull
val releaseKeyAlias = providers.environmentVariable("KAM_RELEASE_KEY_ALIAS").orNull
val releaseKeyPassword = providers.environmentVariable("KAM_RELEASE_KEY_PASSWORD").orNull
val hasReleaseSigning = listOf(
    releaseStoreFile,
    releaseStorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
).all { !it.isNullOrBlank() }

android {
    namespace = "com.aj.kam"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.aj.kam"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    if (hasReleaseSigning) {
        signingConfigs {
            create("release") {
                storeFile = file(requireNotNull(releaseStoreFile))
                storePassword = requireNotNull(releaseStorePassword)
                keyAlias = requireNotNull(releaseKeyAlias)
                keyPassword = requireNotNull(releaseKeyPassword)
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
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

// Refuse release artifact tasks without a complete signing configuration. This
// keeps debug builds usable while preventing an accidentally unsigned or
// debug-signed artifact from being mistaken for a distributable release.
gradle.taskGraph.whenReady {
    val requestsReleaseArtifact = allTasks.any {
        it.name == "assembleRelease" || it.name == "bundleRelease"
    }
    if (requestsReleaseArtifact && !hasReleaseSigning) {
        throw GradleException(
            "Release signing is not configured. Set KAM_RELEASE_STORE_FILE, " +
                "KAM_RELEASE_STORE_PASSWORD, KAM_RELEASE_KEY_ALIAS, and " +
                "KAM_RELEASE_KEY_PASSWORD through a secure local/CI environment."
        )
    }
}
