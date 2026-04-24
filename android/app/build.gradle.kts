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

flutter {
    source = "../.."
}

dependencies {
    // ❗ SMBJ에서 중복되는 암호화 라이브러리 제외
    implementation("com.hierynomus:smbj:0.13.0") {
        exclude(group = "org.bouncycastle", module = "bcprov-jdk18on")
    }
    
    // ❗ jCIFS-ng에서 중복되는 암호화 라이브러리 제외
    implementation("org.codelibs:jcifs:2.1.34") {
        exclude(group = "org.bouncycastle", module = "bcprov-jdk18on")
    }
    
    // ❗ 우리가 정한 단 하나의 통합 암호화 라이브러리 사용
    implementation("org.bouncycastle:bcprov-jdk15to18:1.78")
    
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
}
