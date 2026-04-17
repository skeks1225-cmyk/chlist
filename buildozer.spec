[app]
title = CheckSheetFinal
package.name = checksheetv20
package.domain = org.example
source.dir = .
source.include_exts = py,png,jpg,kv,ttf,pdf,xlsx,json
source.exclude_dirs = backup, bin, .buildozer
version = 2.0

# [체크] 모든 라이브러리 의존성 완벽 보강
requirements = python3,kivy,pyjnius,android,openpyxl,pysmb,pyasn1,six,tqdm,et_xmlfile,jdcal,pycryptodome

orientation = portrait
fullscreen = 0

android.permissions = READ_EXTERNAL_STORAGE, WRITE_EXTERNAL_STORAGE, MANAGE_EXTERNAL_STORAGE, INTERNET, ACCESS_NETWORK_STATE

# [피드백 반영] 라이브러리 버전 barteksc:2.8.2로 고정
android.gradle_dependencies = com.github.barteksc:android-pdf-viewer:2.8.2
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
