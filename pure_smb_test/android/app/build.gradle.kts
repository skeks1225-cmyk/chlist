plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "org.example.smb_scanner_test"
    compileSdk = 34

    defaultConfig {
        applicationId = "org.example.smb_scanner_test"
        minSdk = 24
        targetSdk = 34
        versionCode = 1
        versionName = "1.0.0"
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
            // 테스트용이므로 최적화 비활성화 (안정성 최우선)
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
    // ❗ 정찰병 라이브러리 딱 하나만 추가
    implementation("org.codelibs:jcifs:2.1.34")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
}
