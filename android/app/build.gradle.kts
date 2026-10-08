import java.io.File

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.texttospeech"
    compileSdk = 36
    ndkVersion = "29.0.13113456"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.texttospeech"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
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
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

tasks.register("copyApkToLocal") {
    doLast {
        val tmpDir = System.getProperty("java.io.tmpdir")
        val srcApk = File(tmpDir, "texttospeech_build/app/outputs/flutter-apk/app-debug.apk")
        val altSrcApk = File(tmpDir, "texttospeech_build/app/outputs/apk/debug/app-debug.apk")
        val sourceFile = if (srcApk.exists()) srcApk else if (altSrcApk.exists()) altSrcApk else null
        if (sourceFile != null) {
            val destDir = File(projectDir, "../../build/app/outputs/flutter-apk")
            destDir.mkdirs()
            sourceFile.copyTo(File(destDir, "app-debug.apk"), overwrite = true)
        }
    }
}

tasks.matching { it.name.startsWith("assemble") }.configureEach {
    finalizedBy("copyApkToLocal")
}
