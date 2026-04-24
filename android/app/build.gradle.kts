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

flutter {
    source = "../.."
}

dependencies {
    // ❗ jCIFS-ng 단일 엔진 체제 (안정성 최우선)
    implementation("org.codelibs:jcifs:2.1.34")
    // 암호화 라이브러리 (NoClassDefFoundError 방지용)
    implementation("org.bouncycastle:bcprov-jdk15to18:1.78")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
}
