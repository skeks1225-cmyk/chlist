[app]
title = CheckSheetFinal
package.name = checksheetfinal
package.domain = org.example
source.dir = .
source.include_exts = py,png,jpg,kv,ttf,pdf,xlsx,json
source.exclude_dirs = backup, bin, .buildozer
version = 1.5

# [체크] 모든 라이브러리 의존성 완벽 보강
requirements = python3,kivy,pyjnius,android,openpyxl,pysmb,pyasn1,six,tqdm,et_xmlfile,jdcal,pycryptodome

orientation = portrait
fullscreen = 0

android.permissions = READ_EXTERNAL_STORAGE, WRITE_EXTERNAL_STORAGE, MANAGE_EXTERNAL_STORAGE, INTERNET, ACCESS_NETWORK_STATE

# [체크] mhiew 라이브러리 및 Jetifier 활성화 (실행 시 크래시 방지 핵심)
android.gradle_dependencies = com.github.mhiew:android-pdf-viewer:3.2.0-beta.1
android.gradle_repositories = https://jitpack.io
android.enable_androidx = True
android.enable_jetifier = True

# [체크] 안정적인 빌드를 위한 API 레벨
android.api = 33
android.minapi = 21
android.ndk_api = 21
android.accept_sdk_license = True

[buildozer]
log_level = 2
warn_on_root = 0
