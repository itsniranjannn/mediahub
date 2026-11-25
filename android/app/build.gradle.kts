import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: android/key.properties (git-ignored) points at the private family keystore.
// A release build WITHOUT it is refused: a debug-signed "release" could not update the phones
// (Android would ask to uninstall first, which deletes every download). For a quick local test
// only, pass -PallowDebugSigning (or -Pmediahub.allowDebugSignedRelease=true) to sign with the debug key anyway.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
// -PallowDebugSigning (any value but "false") is the short spelling of the same switch.
val allowDebugSignedRelease = (findProperty("mediahub.allowDebugSignedRelease") as String?) == "true" ||
    (findProperty("allowDebugSigning") as String?).let { it != null && it != "false" }

// Which CPU types the APK carries native code for. The family phones are all arm64, so release
// builds ship arm64-v8a only (youtubedl-android's Python and ffmpeg payloads are ~4x smaller that
// way). tools/device/build_apks.sh passes -Pmediahub.abis=x86_64 for the emulator modes. A debug
// build without the property keeps every ABI so `flutter run` still works on any emulator.
// (Not --split-per-abi: that would change the version codes the phones update by.)
val allAbis = listOf("arm64-v8a", "armeabi-v7a", "x86", "x86_64")
val shippedAbis: List<String>? = (findProperty("mediahub.abis") as String?)
    ?.split(",")?.map { it.trim() }?.filter { it.isNotEmpty() }
val buildsReleaseTask = gradle.startParameter.taskNames.any { it.contains("Release") }
val effectiveAbis: List<String>? = shippedAbis ?: if (buildsReleaseTask) listOf("arm64-v8a") else null

gradle.taskGraph.whenReady {
    val buildsRelease = allTasks.any { it.project == project && it.name.contains("Release") }
    if (buildsRelease && keystoreProperties.isEmpty() && !allowDebugSignedRelease) {
        throw GradleException(
            "android/key.properties is missing, so the release build cannot be signed with the " +
                "family key. Restore key.properties and the keystore from your backup " +
                "(see docs/ROADMAP.md, 'Builds'), or build a debug APK instead."
        )
    }
}

android {
    namespace = "com.example.mediahub"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.mediahub.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        effectiveAbis?.let { abis ->
            ndk {
                abiFilters.clear()
                abiFilters.addAll(abis)
            }
        }
    }

    signingConfigs {
        create("family") {
            if (keystoreProperties.isNotEmpty()) {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // The debug key only when asked for explicitly (docs/DECISIONS.md #19); without
            // key.properties and without the switch the task graph check above stops the build,
            // and no signing config is set, so nothing can quietly fall back to the debug key.
            signingConfig = when {
                keystoreProperties.isNotEmpty() -> signingConfigs.getByName("family")
                allowDebugSignedRelease -> signingConfigs.getByName("debug")
                else -> null
            }
            // Smaller, harder to read, not debuggable.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    // Plugin assets MediaHub never loads: flutter_inappwebview's offline T-Rex page and its web
    // (browser) support script. aapt's own defaults (dot files, CVS, thumbs.db ...) stay listed.
    androidResources {
        ignoreAssetsPatterns += listOf(
            "!.svn", "!.git", "!.ds_store", "!*.scc", ".*", "<dir>_*", "!CVS", "!thumbs.db",
            "!picasa.ini", "!*~", "!t_rex_runner", "!web_support.js",
        )
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
            // Belt and braces for the ABI filter above: drop other CPUs' libraries (including
            // youtubedl-android's libpython / libffmpeg payloads) that a dependency adds directly.
            effectiveAbis?.let { abis ->
                for (abi in allAbis - abis.toSet()) excludes += "lib/$abi/**"
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

dependencies {
    // Theme.AppCompat for the local_auth fingerprint dialog on Android 8-11 (App lock).
    implementation("androidx.appcompat:appcompat:1.7.1")
    implementation("io.github.junkfood02.youtubedl-android:library:0.18.1")
    implementation("io.github.junkfood02.youtubedl-android:ffmpeg:0.18.1")
}