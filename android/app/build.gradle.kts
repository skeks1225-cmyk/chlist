plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "org.example.checksheet"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.2.13676358"

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
            // ❗ 정찰병 라이브러리 유실 방지를 위해 R8 최적화 비활성화 유지
            isMinifyEnabled = false
            isShrinkResources = false
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("com.hierynomus:smbj:0.13.0")
    // ❗ [성공 검증됨] jCIFS-ng 추가
    implementation("org.codelibs:jcifs:2.1.34")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
}
