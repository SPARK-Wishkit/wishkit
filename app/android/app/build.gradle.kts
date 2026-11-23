import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

// 출시 서명 키: android/key.properties (git 제외)에서 읽는다. 없으면 release 빌드는 debug 키로
// 서명되어 Play Console 업로드가 거부된다. 만드는 법: docs/play-release/README.md
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
val testAdmobAppId = "ca-app-pub-3940256099942544~3347511713"

android {
    namespace = "com.softstudio.wishlist"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.softstudio.wishlist"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = maxOf(24, flutter.minSdkVersion) // google_mobile_ads 9.x 가 24 이상 요구
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // AdMob 앱 ID: android/gradle.properties 의 admobAndroidAppId. 없으면 구글 테스트 앱 ID.
        manifestPlaceholders["admobAppId"] =
            (project.findProperty("admobAndroidAppId") as String?) ?: testAdmobAppId
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // key.properties 가 있으면 업로드 키로 서명. 없으면 로컬 `flutter run --release` 용으로만
            // debug 키를 쓴다 (이 빌드는 Play Console 에 올릴 수 없다).
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                logger.warn("WishKit: android/key.properties 가 없어 release 빌드를 debug 키로 서명합니다 (Play 업로드 불가).")
                signingConfigs.getByName("debug")
            }
            if ((project.findProperty("admobAndroidAppId") as String?) in listOf(null, testAdmobAppId)) {
                logger.warn("WishKit: AdMob 테스트 앱 ID 로 빌드합니다. 출시 빌드는 gradle.properties 의 admobAndroidAppId 를 바꾸세요.")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}