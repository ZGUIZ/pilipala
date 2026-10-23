import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 签名配置
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

val _storeFile = file(System.getenv("KEYSTORE") ?: keystoreProperties["storeFile"] ?: "vvex.jks")
val _storePassword = System.getenv("KEYSTORE_PASSWORD") ?: keystoreProperties["storePassword"] as String?
val _keyAlias = System.getenv("KEY_ALIAS") ?: keystoreProperties["keyAlias"] as String?
val _keyPassword = System.getenv("KEY_PASSWORD") ?: keystoreProperties["keyPassword"] as String?

android {
    namespace = "com.guozhigq.pilipala"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
    }

    defaultConfig {
        applicationId = "com.guozhigq.pilipala"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    signingConfigs {
        if (file(_storeFile).exists()) {
            create("release") {
                storeFile = _storeFile
                storePassword = _storePassword
                keyAlias = _keyAlias
                keyPassword = _keyPassword
                isV1SigningEnabled = true
                isV2SigningEnabled = true
            }
        }
    }

    buildTypes {
        release {
            // 未提供发布密钥（vvex.jks / key.properties）时回退到 debug 签名，
            // 仅供内部测试；正式发布需补齐密钥并改回 release 签名。
            signingConfig = if (file(_storeFile).exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("org.jetbrains.kotlin:kotlin-stdlib-jdk7:2.2.20")
}
