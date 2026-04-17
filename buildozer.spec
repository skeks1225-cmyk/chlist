[app]
title = CheckSheetApp
package.name = checksheetappv7
package.domain = org.example
source.dir = .
source.include_exts = py,png,jpg,kv,ttf,pdf
source.exclude_dirs = backup, bin, .buildozer
version = 1.3

# [핵심] 모든 기능을 위해 반드시 필요한 라이브러리 목록 복구
requirements = python3,kivy,pyjnius,android,openpyxl,pysmb,pyasn1,six,tqdm,et_xmlfile,jdcal

orientation = portrait
fullscreen = 0

android.permissions = READ_EXTERNAL_STORAGE, WRITE_EXTERNAL_STORAGE, MANAGE_EXTERNAL_STORAGE, INTERNET, ACCESS_NETWORK_STATE

# [해결] 검증된 mhiew 포크 버전 유지
android.gradle_dependencies = com.github.mhiew:android-pdf-viewer:3.2.0-beta.1
android.gradle_repositories = https://jitpack.io

android.enable_androidx = True
android.accept_sdk_license = True

# 안정적인 빌드를 위한 설정
android.api = 33
android.minapi = 21
android.ndk_api = 21

[buildozer]
log_level = 2
warn_on_root = 0
