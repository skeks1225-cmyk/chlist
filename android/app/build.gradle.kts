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
        
        // ❗ Proguard 설정 연결 (Bouncy Castle 보호용)
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
            excludes += "META-INF/versions/9/OSGI-INF/MANIFEST.MF"
        }
    }
}

// ❗ [지피티 추천] 어떤 라이브러리가 무엇을 요구하든 1.78 버전으로 강제 고정 (충돌 방지 핵심)
configurations.all {
    resolutionStrategy {
        force("org.bouncycastle:bcprov-jdk18on:1.78")
    }
}

flutter {
    source = "../.."
}

dependencies {
    // ❗ 1. 고속 전송의 제왕 SMBJ (암호화 라이브러리 중복 제외)
    implementation("com.hierynomus:smbj:0.13.0") {
        exclude(group = "org.bouncycastle", module = "bcprov-jdk18on")
        exclude(group = "org.bouncycastle", module = "bcprov-jdk15on")
    }
    
    // ❗ 2. 탐색의 달인 jCIFS-ng (암호화 라이브러리 중복 제외)
    implementation("org.codelibs:jcifs:2.1.34") {
        exclude(group = "org.bouncycastle", module = "bcprov-jdk18on")
        exclude(group = "org.bouncycastle", module = "bcprov-jdk15on")
    }
    
    // ❗ 3. 두 라이브러리가 공동으로 사용할 암호화 엔진 딱 하나만 탑재
    implementation("org.bouncycastle:bcprov-jdk18on:1.78")
    
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
}
