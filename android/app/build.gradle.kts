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

    // ❗ [수정] 서명 파일(*.SF, *.RSA)은 제외하지 않습니다. (에러 해결 핵심)
    packaging {
        resources {
            pickFirst("META-INF/versions/9/OSGI-INF/MANIFEST.MF")
            excludes += "META-INF/NOTICE"
            excludes += "META-INF/LICENSE"
            excludes += "META-INF/DEPENDENCIES"
        }
    }
}

// ❗ Bouncy Castle 버전 강제 고정
configurations.all {
    resolutionStrategy {
        force("org.bouncycastle:bcprov-jdk18on:1.78.1")
    }
}

flutter {
    source = "../.."
}

dependencies {
    // jCIFS-ng 단일 엔진 체제
    implementation("org.codelibs:jcifs:2.1.34")
    implementation("org.bouncycastle:bcprov-jdk18on:1.78.1")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
}
