[app]
title = CheckSheet
package.name = checksheetapp
package.domain = org.example
source.dir = .
source.include_exts = py,png,jpg,kv,atlas,ttf,xlsx,json
version = 1.0

# [수정] 필수 라이브러리 최소 구성
requirements = python3,kivy,openpyxl,et_xmlfile,jdcal,pyjnius,android,pysmb,pyasn1,six

orientation = portrait
fullscreen = 0

# [수정] 오프라인 파일 접근 및 네트워크 권한
android.permissions = READ_EXTERNAL_STORAGE, WRITE_EXTERNAL_STORAGE, MANAGE_EXTERNAL_STORAGE, INTERNET, ACCESS_NETWORK_STATE

# [수정] Native PDF Viewer 라이브러리 의존성
android.gradle_dependencies = com.github.barteksc:android-pdf-viewer:2.8.2

# [수정] AndroidX 및 Jetifier 활성화 (크래시 방지 핵심)
android.enable_androidx = True
android.gradle_options = android.useAndroidX=true, android.enableJetifier=true

# Android API 설정
android.api = 33
android.minapi = 21
android.accept_sdk_license = True

[buildozer]
log_level = 2
warn_on_root = 0
