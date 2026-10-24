plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "io.sofluffy.raccoon.runtime.pocket"
    // permission_handler_android 14 compiles against 37; Flutter 3.47's
    // default is 36.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications needs java.time on older Androids.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "io.sofluffy.raccoon.runtime.pocket"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // What a project's SDK must match; tool/build_apk.sh sets them.
        resValue("string", "rr_flutter_version", System.getenv("RR_FLUTTER_VERSION") ?: "unknown")
        resValue("string", "rr_engine_revision", System.getenv("RR_ENGINE_REVISION") ?: "unknown")
    }

    buildFeatures {
        resValues = true
    }

    // The debug engine's Vulkan validation layer (14.5 MB on arm64) loads only
    // when validation is switched on in the manifest, which RR Pocket never does.
    packaging {
        jniLibs {
            excludes += "**/libVkLayer_khronos_validation.so"
        }
    }

    // RR Pocket ships Flutter's debug engine: tool/build_apk.sh builds the
    // debug type and turns android:debuggable off afterwards.
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
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // Scan to pair: Google's scanner runs in Play services, without the
    // camera permission; qr_code_scanner_plus is the fallback without it.
    implementation("com.google.android.gms:play-services-code-scanner:16.1.0")
    testImplementation("junit:junit:4.13.2")
    // Android's org.json is a stub in unit tests; /pair parses JSON.
    testImplementation("org.json:json:20250517")
}
