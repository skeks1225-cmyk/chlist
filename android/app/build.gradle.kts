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
            isMinifyEnabled = false
            isShrinkResources = false
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    packaging {
        resources {
            excludes += "META-INF/*"
        }
    }
}

// ❗ [핵심 해결책] 프로젝트 내의 모든 Bouncy Castle 버전을 1.78 하나로 강제 통일
configurations.all {
    resolutionStrategy {
        force("org.bouncycastle:bcprov-jdk18on:1.78.1")
    }
}

flutter {
    source = "../.."
}

dependencies {
    // ❗ jCIFS-ng 단일 엔진 (내부적으로 1.71 버전을 부르지만 위의 force 설정이 1.78로 승격시킴)
    implementation("org.codelibs:jcifs:2.1.34")
    
    // ❗ 우리가 사용할 표준 암호화 라이브러리 하나만 명시
    implementation("org.bouncycastle:bcprov-jdk18on:1.78.1")
    
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
}
