plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// lib/design_tokens is a committed symlink to ../../kkeujeok-web/design_tokens (inside lib/
// because the Dart analyzer rejects relative imports that leave lib/). Builds fail early, and
// say why, when it is not usable. The check runs with the build (preBuild), not while Gradle
// configures, so tasks that need no tokens (signingReport, clean) still work.
val checkDesignTokens = tasks.register("checkDesignTokens") {
    val clientRoot = rootProject.projectDir.parentFile
    doLast {
        val link = File(clientRoot, "lib/design_tokens")
        val sibling = File(clientRoot, "../kkeujeok-web/design_tokens")
        if (link.isFile) {
            throw GradleException(
                "lib/design_tokens가 심링크가 아니라 파일로 체크아웃됨. `git config core.symlinks true`를 확인하고 " +
                    "다시 체크아웃하세요. (lib/design_tokens was checked out as a plain file, not a symlink.)"
            )
        }
        if (!sibling.isDirectory) {
            throw GradleException(
                "kkeujeok-web 형제 클론 필요: ${sibling.path} 가 없습니다. " +
                    "(Clone kkeujeok-web next to kkeujeok-client inside the root kkeujeok repo.)"
            )
        }
        if (!File(link, "build/tokens.dart").isFile) {
            throw GradleException(
                "lib/design_tokens/build/tokens.dart 를 찾을 수 없음: lib/design_tokens가 ../../kkeujeok-web/design_tokens 를 " +
                    "가리키는지 확인하세요. (Missing lib/design_tokens/build/tokens.dart.)"
            )
        }
    }
}
tasks.matching { it.name == "preBuild" }.configureEach { dependsOn(checkDesignTokens) }

android {
    namespace = "com.kkeujeok.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.kkeujeok.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 29
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
