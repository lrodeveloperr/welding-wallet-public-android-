import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use(keystoreProperties::load)
}

val googleDemoAdMobAppId = "ca-app-pub-3940256099942544~3347511713"
val approvedAdMobPublisherId = "8054612600809568"
val productionAdMobAppId = providers
    .environmentVariable("WELDING_ADMOB_ANDROID_APP_ID")
    .orElse(providers.gradleProperty("WELDING_ADMOB_ANDROID_APP_ID"))
    .orNull
val approvedProductionAdMobApp = Regex(
    "^ca-app-pub-$approvedAdMobPublisherId~\\d{10}$",
)

android {
    namespace = "com.goodusestudios.weldinggaswallet"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.goodusestudios.weldinggaswallet"
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        multiDexEnabled = true
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["ADMOB_APP_ID"] = googleDemoAdMobAppId
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            manifestPlaceholders["ADMOB_APP_ID"] = productionAdMobAppId ?: "MISSING_ADMOB_APP_ID"
            if (keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

tasks.configureEach {
    if (name.contains("release", ignoreCase = true)) {
        doFirst {
            require(
                productionAdMobAppId != null &&
                    approvedProductionAdMobApp.matches(productionAdMobAppId),
            ) {
                "Release requires WELDING_ADMOB_ANDROID_APP_ID owned by publisher $approvedAdMobPublisherId."
            }
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
