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
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        
        proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
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
            // ❗ 라이브러리 유실 방지를 위해 최적화 비활성화
            isMinifyEnabled = false
            isShrinkResources = false
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    // ❗ [지옥 탈출 핵심] 중복 파일 충돌을 모든 경로에서 완벽히 차단
    packaging {
        resources {
            excludes += "META-INF/**"
            excludes += "META-INF/versions/9/OSGI-INF/MANIFEST.MF"
            excludes += "OSGI-INF/**"
        }
    }
}

// ❗ 라이브러리 간 버전 전쟁 종식 (1.78.1로 강제 통일)
configurations.all {
    resolutionStrategy {
        force("org.bouncycastle:bcprov-jdk18on:1.78.1")
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("org.codelibs:jcifs:2.1.34")
    implementation("org.bouncycastle:bcprov-jdk18on:1.78.1")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
}
