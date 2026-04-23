plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "org.example.checksheet"
    compileSdk = flutter.compileSdkVersion

    defaultConfig {
        applicationId = "org.example.checksheet"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

// ❗ 이 블록이 없으면 io.flutter 패키지를 찾지 못해 빌드가 터집니다.
flutter {
    source = "../.."
}

dependencies {
    implementation("com.hierynomus:smbj:0.13.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
}
